import '../regex/catalyst_patterns.dart';

class CatalystParseResult {
  final List<String> tags;
  final bool blockedByPromptInjection;

  const CatalystParseResult({required this.tags, required this.blockedByPromptInjection});
}

/// Deterministic regex catalyst engine — spec Module 2 §3.
class CatalystParser {
  CatalystParser._();

  /// Strips HTML tags and zero-width/invisible characters before any
  /// pattern matching runs, per spec.
  static String sanitize(String rawText) {
    var text = rawText.replaceAll(CatalystPatterns.htmlTag, ' ');
    text = text.replaceAll(CatalystPatterns.zeroWidthChars, '');
    // Collapse excess whitespace left behind by tag stripping.
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Runs the full pipeline: sanitize -> prompt-injection block -> structural
  /// catalyst tagging. If prompt-injection language is detected, the filing
  /// is excluded from catalyst tagging entirely (tags come back empty) and
  /// `blockedByPromptInjection` is true.
  static CatalystParseResult parse(String rawText) {
    final clean = sanitize(rawText);

    if (CatalystPatterns.promptInjectionBlock.hasMatch(clean)) {
      return const CatalystParseResult(tags: [], blockedByPromptInjection: true);
    }

    final tags = <String>[];
    CatalystPatterns.structuralCatalysts.forEach((tag, pattern) {
      if (pattern.hasMatch(clean)) tags.add(tag);
    });

    return CatalystParseResult(tags: tags, blockedByPromptInjection: false);
  }
}
