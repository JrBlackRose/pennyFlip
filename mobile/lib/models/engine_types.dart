/// Narrow interfaces the quant engine modules (Pattern Hunter, Backtest
/// Engine) depend on, instead of depending directly on the sqflite-backed
/// models. This keeps Modules 2 and 3 runnable against synthetic fixture
/// data in the on-device self-test harness, with zero database or network
/// dependency.
abstract class OhlcvBarLike {
  double get open;
  double get high;
  double get low;
  double get close;
  double get volume;
}

abstract class FilingTextLike {
  String get text;
  String get formType;
}
