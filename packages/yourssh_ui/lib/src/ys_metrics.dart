/// Spacing scale.
abstract final class YsSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
}

/// Corner radii.
abstract final class YsRadius {
  static const double control = 6;
  static const double card = 10;
  static const double mobileCard = 14;
}

/// Font family; files are bundled by the app.
const String kYsFontFamily = 'Inter';

/// Monospace font family (bundled by the app) for hostnames, paths and code.
const String kYsMonoFontFamily = 'MesloLGS NF';

/// Fallbacks when [kYsMonoFontFamily] is unavailable.
const List<String> kYsMonoFontFallback = [
  'Roboto Mono for Powerline',
  'Menlo',
  'Consolas',
  'monospace',
];
