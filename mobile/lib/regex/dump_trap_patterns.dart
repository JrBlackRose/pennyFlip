/// Crash-correlation / dilution-risk regex dictionary (spec Module 3 §1).
///
/// These patterns exist to VETO setups, protecting the user from walking
/// into a toxic-financing dump trap — they are a defensive filter, not a
/// trading signal to act on.
class DumpTrapPatterns {
  DumpTrapPatterns._();

  static final Map<String, RegExp> crashCorrelationText = {
    'toxic_convertible_note': RegExp(
      r'\b(?:variable\s+conversion\s+price|discount\s+to\s+the\s+lowest\s+trading\s+price|toxic\s+note|death\s+spiral)\b',
      caseSensitive: false,
    ),
    'active_atm_or_424b5_dilution': RegExp(
      r'\b(?:at-the-market\s+offering|prospectus\s+supplement\s+pursuant\s+to\s+rule\s+424\(b\)\(5\)|equity\s+line\s+of\s+credit|eloc)\b',
      caseSensitive: false,
    ),
    'warrant_ratchet_reset': RegExp(
      r'\b(?:full-ratchet\s+anti-dilution|warrant\s+exercise\s+price\s+reset|cashless\s+exercise\s+provision)\b',
      caseSensitive: false,
    ),
    'reverse_split_proposal': RegExp(
      r'\b(?:reverse\s+stock\s+split\s+in\s+a\s+ratio|nasdaq\s+minimum\s+bid\s+price\s+deficiency)\b',
      caseSensitive: false,
    ),
    'insider_form4_liquidation': RegExp(
      r'\b(?:disposition\s+of\s+shares\s+by\s+chief\s+executive|rule\s+10b5-1\s+liquidation)\b',
      caseSensitive: false,
    ),
  };

  /// SEC forms that trigger an immediate veto on their own, independent of
  /// filing text (spec Module 3 §1).
  static const vetoForms = {'S-3', 'S-3/A', '424B5', 'S-1', 'EFFECT'};
}
