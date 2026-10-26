import '../models/filing.dart';

/// Deterministic, fully offline OHLCV fixture used by the on-device
/// self-test (spec section "Run Self-Test" button).
///
/// Shape (150 bars, oldest -> newest, index 149 is the breakout bar):
///   [0..58]    59 filler bars — outside every Module 2/3 window, exist only
///              to satisfy the 150-bar minimum history requirement.
///   [59..98]   40 bars flat at 3.30 — establishes the 90-day low.
///   [99..128]  30 bars, the "prior 30d baseline" window: busier, rising
///              3.30 -> ~4.13, mean volume ~2,000,000 (the noisy period
///              right before the quiet accumulation base).
///   [129..148] 20 bars, the accumulation base: tight 4.00-4.26 range
///              (6.5% bandwidth, inside the 5-8% band) on ~400k mean volume
///              (dry-up ≈ 80%, inside the 70-90% band).
///   [149]      the breakout bar: gaps to a new 90-day high/close with a
///               5,000,000-share volume surge (>2.5x the 15-day average).
///
/// Worked by hand in the self-test design notes:
///   bandwidth ≈ 6.5%, volume dry-up ≈ 80%, latest_close hugs the top 3% of
///   the 90d range, volume surge ≈ 5x, projected upside ≈ 33.6%, ATR_10 ≈
///   0.134 -> synthetic spread ≈ 4.5% (floored to the 15% minimum), net
///   expected edge ≈ 18.6% (clears the +10% minimum) -> Module 2 and Module
///   3 both PASS with no veto triggers.
class FixtureBar {
  final double open, high, low, close, volume;
  const FixtureBar(this.open, this.high, this.low, this.close, this.volume);
}

List<FixtureBar> buildPassFixtureBars() {
  final bars = <FixtureBar>[];

  // [0..58] filler — flat, unused by any window.
  for (var i = 0; i < 59; i++) {
    bars.add(const FixtureBar(3.00, 3.00, 3.00, 3.00, 500000));
  }

  // [59..98] 40 bars flat at 3.30 — sets the 90-day low.
  for (var i = 0; i < 40; i++) {
    bars.add(const FixtureBar(3.30, 3.30, 3.30, 3.30, 500000));
  }

  // [99..128] 30 baseline bars, rising gently 3.30 -> ~4.13, vol = 2,000,000.
  for (var i = 0; i < 30; i++) {
    final close = 3.30 + (i * (0.83 / 29));
    final open = i == 0 ? 3.30 : (3.30 + ((i - 1) * (0.83 / 29)));
    bars.add(FixtureBar(open, close + 0.05, close - 0.05, close, 2000000));
  }

  // [129..148] 20 base bars, tight 4.00-4.26 range, ~400k volume, with one
  // bar forced to the window high (j=5) and one forced to the window low
  // (j=14) so bandwidth is exactly (4.26-4.00)/4.00 = 6.5%.
  double prevClose = 3.30 + (29 * (0.83 / 29)); // last baseline close ≈ 4.13
  for (var j = 0; j < 20; j++) {
    final close = 4.10 + 0.01 * (j % 4);
    final isHighDay = j == 5;
    final isLowDay = j == 14;
    final high = isHighDay ? 4.26 : close + 0.05;
    final low = isLowDay ? 4.00 : close - 0.05;
    final open = prevClose;
    final volume = 380000.0 + 20000.0 * (j % 3);
    bars.add(FixtureBar(open, high, low, close, volume));
    prevClose = close;
  }

  // [149] breakout bar — gaps up, new 90d high/close, volume surge.
  bars.add(const FixtureBar(4.30, 4.50, 4.28, 4.46, 5000000));

  return bars;
}

/// A single recent 8-K with clean, unambiguous catalyst language: matches
/// `definitive_agreement` and nothing in the dump-trap dictionary.
Filing buildPassCatalystFiling(String cik10) {
  return Filing(
    cik10: cik10,
    accessionNumber: 'self-test-8k-pass',
    formType: '8-K',
    filedAt: DateTime.now().subtract(const Duration(days: 2)),
    cachedText:
        'On the Closing Date, the Company entered into a definitive merger agreement '
        'with the Target to acquire all outstanding equity interests, subject to '
        'customary closing conditions and regulatory approvals.',
  );
}

/// A recent 8-K whose language matches TWO Module 3 dump-trap regexes, used
/// by the HPMP veto fixture: `toxic_convertible_note` and
/// `active_atm_or_424b5_dilution`.
Filing buildDumpTrapCatalystFiling(String cik10) {
  return Filing(
    cik10: cik10,
    accessionNumber: 'self-test-8k-veto',
    formType: '8-K',
    filedAt: DateTime.now().subtract(const Duration(days: 1)),
    cachedText:
        'The Company entered into a definitive purchase agreement for a funding tranche '
        'structured as a convertible note bearing a variable conversion price equal to a '
        'discount to the lowest trading price, and separately established an '
        'at-the-market offering facility pursuant to an effective shelf registration.',
  );
}
