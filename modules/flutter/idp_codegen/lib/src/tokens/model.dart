/// A colour with its light and dark values.
class ColorToken {
  ColorToken({required this.name, required this.light, required this.dark});

  final String name;

  /// 0xAARRGGBB, ready to drop into a Dart `Color` literal.
  final int light;
  final int dark;

  bool get isModeIndependent => light == dark;
}

class TypographyToken {
  TypographyToken({
    required this.name,
    required this.size,
    this.weight = 400,
    this.height,
    this.letterSpacing,
  });

  final String name;
  final double size;
  final int weight;

  /// Multiplier, not pixels — Flutter's `TextStyle.height` is relative to
  /// font size, and a design tool exporting `lineHeight: 24` for a 16px font
  /// means 1.5 here.
  final double? height;
  final double? letterSpacing;
}

class TokenSet {
  TokenSet({
    required this.sourcePath,
    this.colors = const [],
    this.spacing = const {},
    this.radii = const {},
    this.typography = const [],
    this.fontFamily,
  });

  final String sourcePath;
  final List<ColorToken> colors;
  final Map<String, double> spacing;
  final Map<String, double> radii;
  final List<TypographyToken> typography;
  final String? fontFamily;

  ColorToken? color(String name) {
    for (final token in colors) {
      if (token.name == name) return token;
    }
    return null;
  }
}

/// Colour roles that map onto Flutter's [ColorScheme].
///
/// Requiring these is what makes the generated theme work with stock Material
/// widgets. Without a real `ColorScheme`, every Material widget in the app
/// keeps its default blue and the token file only colours the handful of
/// widgets that read the extension — which is the usual way a design system
/// ends up half-applied.
const requiredColorRoles = [
  'primary',
  'on_primary',
  'secondary',
  'on_secondary',
  'surface',
  'on_surface',
  'error',
  'on_error',
];
