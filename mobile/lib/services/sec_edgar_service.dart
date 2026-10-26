import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/entity.dart';
import '../models/filing.dart';
import 'settings_service.dart';

/// SEC EDGAR ingestion layer — spec Module 1.
///
/// Rate limiting: SEC's fair-access policy allows up to 10 requests/second
/// with a declared User-Agent. We throttle to one request per 120ms
/// (< 10 req/sec) regardless of caller concurrency, via a simple serialized
/// request queue.
class SecEdgarService {
  SecEdgarService._internal();
  static final SecEdgarService instance = SecEdgarService._internal();

  static const _throttle = Duration(milliseconds: 120);
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  final _lock = _AsyncLock();

  Future<http.Response> _get(Uri uri) async {
    return _lock.synchronized(() async {
      final waitFor = _throttle - DateTime.now().difference(_lastRequestAt);
      if (waitFor > Duration.zero) {
        await Future<void>.delayed(waitFor);
      }
      final userAgent = await SettingsService.instance.getSecUserAgent();
      final resp = await http.get(uri, headers: {
        'User-Agent': userAgent,
        'Accept-Encoding': 'gzip, deflate',
        'Host': uri.host,
      });
      _lastRequestAt = DateTime.now();
      return resp;
    });
  }

  /// Master CIK directory: https://www.sec.gov/files/company_tickers.json
  /// Returns a map of ticker -> 10-digit zero-padded CIK + company name.
  Future<List<Entity>> fetchMasterCikDirectory() async {
    final resp = await _get(Uri.parse('https://www.sec.gov/files/company_tickers.json'));
    if (resp.statusCode != 200) {
      throw SecEdgarException('company_tickers.json failed: ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final now = DateTime.now();
    final out = <Entity>[];
    for (final entry in decoded.values) {
      final m = entry as Map<String, dynamic>;
      final cik = (m['cik_str'] as num).toInt();
      final cik10 = cik.toString().padLeft(10, '0');
      out.add(Entity(
        cik10: cik10,
        name: m['title'] as String? ?? '',
        latestTicker: m['ticker'] as String?,
        lastSyncedAt: now,
      ));
    }
    return out;
  }

  /// Entity submissions & delisting check:
  /// https://data.sec.gov/submissions/CIK{10_digit_cik}.json
  Future<SubmissionsResult> fetchSubmissions(String cik10) async {
    final resp = await _get(Uri.parse('https://data.sec.gov/submissions/CIK$cik10.json'));
    if (resp.statusCode != 200) {
      throw SecEdgarException('submissions failed for $cik10: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;

    final tickers = (body['tickers'] as List<dynamic>? ?? []).cast<String>();
    final exchanges = (body['exchanges'] as List<dynamic>? ?? []).cast<String>();

    final recent = (body['filings']?['recent'] as Map<String, dynamic>?) ?? {};
    final formTypes = (recent['form'] as List<dynamic>? ?? []).cast<String>();
    final accessionNumbers = (recent['accessionNumber'] as List<dynamic>? ?? []).cast<String>();
    final filingDates = (recent['filingDate'] as List<dynamic>? ?? []).cast<String>();
    final primaryDocs = (recent['primaryDocument'] as List<dynamic>? ?? []).cast<String?>();

    final filings = <Filing>[];
    for (var i = 0; i < formTypes.length; i++) {
      filings.add(Filing(
        cik10: cik10,
        accessionNumber: accessionNumbers.length > i ? accessionNumbers[i] : '$i',
        formType: formTypes[i],
        filedAt: filingDates.length > i ? DateTime.parse(filingDates[i]) : DateTime.now(),
        primaryDocUrl: (primaryDocs.length > i && primaryDocs[i] != null)
            ? 'https://www.sec.gov/Archives/edgar/data/${int.parse(cik10)}/'
                '${(accessionNumbers.length > i ? accessionNumbers[i] : '').replaceAll('-', '')}/'
                '${primaryDocs[i]}'
            : null,
      ));
    }

    // Flag is_delisted = 1 if tickers is empty OR recent forms contain any
    // deregistration form per spec.
    final hasDelistingForm = formTypes.any((f) => Filing.delistingForms.contains(f));
    final isDelisted = tickers.isEmpty || hasDelistingForm;

    return SubmissionsResult(
      cik10: cik10,
      name: body['name'] as String? ?? '',
      tickers: tickers,
      exchanges: exchanges,
      isDelisted: isDelisted,
      filings: filings,
    );
  }

  /// XBRL outstanding float count:
  /// https://data.sec.gov/api/xbrl/companyfacts/CIK{10_digit_cik}.json
  /// -> facts.dei.EntityCommonStockSharesOutstanding.units.shares[-1].val
  Future<double?> fetchSharesOutstanding(String cik10) async {
    final resp =
        await _get(Uri.parse('https://data.sec.gov/api/xbrl/companyfacts/CIK$cik10.json'));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw SecEdgarException('companyfacts failed for $cik10: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final shares = body['facts']?['dei']?['EntityCommonStockSharesOutstanding']?['units']?['shares']
        as List<dynamic>?;
    if (shares == null || shares.isEmpty) return null;
    final last = shares.last as Map<String, dynamic>;
    return (last['val'] as num?)?.toDouble();
  }

  /// Fetches the raw primary document text for a filing (used by the Module
  /// 2 catalyst parser and the Module 3 crash-correlation text scan).
  Future<String?> fetchFilingText(Filing filing) async {
    if (filing.primaryDocUrl == null) return null;
    final resp = await _get(Uri.parse(filing.primaryDocUrl!));
    if (resp.statusCode != 200) return null;
    return resp.body;
  }
}

class SubmissionsResult {
  final String cik10;
  final String name;
  final List<String> tickers;
  final List<String> exchanges;
  final bool isDelisted;
  final List<Filing> filings;

  const SubmissionsResult({
    required this.cik10,
    required this.name,
    required this.tickers,
    required this.exchanges,
    required this.isDelisted,
    required this.filings,
  });
}

class SecEdgarException implements Exception {
  final String message;
  SecEdgarException(this.message);
  @override
  String toString() => 'SecEdgarException: $message';
}

/// Minimal async mutex so concurrent callers still serialize through the
/// 120ms SEC throttle instead of racing _lastRequestAt.
class _AsyncLock {
  Future<void> _chain = Future.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final result = _chain.then((_) => action());
    _chain = _chain.then((_) => completer.future).catchError((_) {});
    result.whenComplete(() => completer.complete());
    return result;
  }
}
