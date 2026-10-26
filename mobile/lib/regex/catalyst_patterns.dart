/// Deterministic regex catalyst engine (spec Module 2 §3). No LLM calls —
/// every tag is a plain regular expression match against sanitized filing
/// text, so results are reproducible and auditable.
class CatalystPatterns {
  CatalystPatterns._();

  /// Zero-width / invisible characters stripped before matching, so a
  /// filing can't hide or split a trigger phrase across an invisible
  /// character boundary.
  static final zeroWidthChars = RegExp('[​‌‍﻿]');

  static final htmlTag = RegExp(r'<[^>]+>');

  /// Prompt-injection / hype-language block list. A filing whose text
  /// matches this is excluded from catalyst tagging entirely — it is
  /// treated as untrusted, manipulated content, not as a legitimate
  /// structural catalyst, regardless of what else it contains.
  static final promptInjectionBlock = RegExp(
    r'\b(?:ignore\s+all\s+previous\s+instructions|system\s+prompt|guaranteed\s+100x|short\s+squeeze\s+imminent)\b',
    caseSensitive: false,
  );

  /// Structural catalyst tags. Each is independent; a filing can match zero,
  /// one, or several.
  static final Map<String, RegExp> structuralCatalysts = {
    'definitive_agreement': RegExp(
      r'\bdefinitive\s+(?:merger\s+|purchase\s+|asset\s+)?agreement\b',
      caseSensitive: false,
    ),
    'funding_tranche': RegExp(
      r'\bfunding\s+tranche\b|\bnon-dilutive\s+(?:financing|grant|funding)\b',
      caseSensitive: false,
    ),
    'proprietary_asset_acquisition': RegExp(
      r'\bproprietary\s+asset\s+acquisition\b|\bacquired\s+100%\s+of\b',
      caseSensitive: false,
    ),
    'government_or_dod_contract': RegExp(
      r'\b(?:dod|department\s+of\s+defense|government)\s+contract\s+award(?:ed)?\b',
      caseSensitive: false,
    ),
    'fda_or_clinical_milestone': RegExp(
      r'\b(?:fda\s+clearance|fda\s+approval|primary\s+endpoint\s+met)\b',
      caseSensitive: false,
    ),
    'debt_extinguishment': RegExp(
      r'\bextinguishment\s+of\s+(?:all\s+)?convertible\s+debt\b',
      caseSensitive: false,
    ),
  };
}
