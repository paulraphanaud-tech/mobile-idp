import '../naming.dart';
import 'model.dart';

/// Material's TextTheme slots. A typography token named after one of these is
/// wired into the TextTheme as well as the extension, so stock widgets pick it
/// up without every call site reaching for the extension.
const _materialTextSlots = {
  'display_large', 'display_medium', 'display_small',
  'headline_large', 'headline_medium', 'headline_small',
  'title_large', 'title_medium', 'title_small',
  'body_large', 'body_medium', 'body_small',
  'label_large', 'label_medium', 'label_small',
};

String generateTokensDart(TokenSet tokens, {String? command}) {
  final buffer = StringBuffer()
    ..write(generatedHeader(tokens.sourcePath, command ?? 'make design-tokens'))
    ..writeln()
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln();

  _writeColors(buffer, tokens);
  if (tokens.spacing.isNotEmpty) {
    _writeScale(buffer, 'AppSpacing', 'spacing', tokens.spacing);
  }
  if (tokens.radii.isNotEmpty) {
    _writeScale(buffer, 'AppRadii', 'corner radius', tokens.radii);
  }
  if (tokens.typography.isNotEmpty) _writeTypography(buffer, tokens);
  _writeTheme(buffer, tokens);
  _writeContextExtension(buffer, tokens);

  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------

void _writeColors(StringBuffer buffer, TokenSet tokens) {
  final fields = tokens.colors.map((c) => toLowerCamel(c.name)).toList();

  buffer
    ..writeln('/// Every colour token, in both modes.')
    ..writeln('///')
    ..writeln('/// Reachable as `context.colors.primary`. Registered as a')
    ..writeln('/// [ThemeExtension] so it follows the ambient theme rather than')
    ..writeln('/// being read from a global, which is what lets a subtree be')
    ..writeln('/// re-themed and what makes widget tests able to override it.')
    ..writeln('@immutable')
    ..writeln('class AppColors extends ThemeExtension<AppColors> {')
    ..writeln('  const AppColors({');
  for (final field in fields) {
    buffer.writeln('    required this.$field,');
  }
  buffer
    ..writeln('  });')
    ..writeln();

  for (final color in tokens.colors) {
    if (color.isModeIndependent) {
      buffer.writeln('  /// Same in light and dark.');
    }
    buffer.writeln('  final Color ${toLowerCamel(color.name)};');
  }
  buffer.writeln();

  for (final mode in ['light', 'dark']) {
    buffer.writeln('  static const AppColors $mode = AppColors(');
    for (final color in tokens.colors) {
      final value = mode == 'light' ? color.light : color.dark;
      buffer.writeln(
          '    ${toLowerCamel(color.name)}: Color(0x${value.toRadixString(16).padLeft(8, '0').toUpperCase()}),');
    }
    buffer
      ..writeln('  );')
      ..writeln();
  }

  buffer
    ..writeln('  @override')
    ..writeln('  AppColors copyWith({');
  for (final field in fields) {
    buffer.writeln('    Color? $field,');
  }
  buffer
    ..writeln('  }) =>')
    ..writeln('      AppColors(');
  for (final field in fields) {
    buffer.writeln('        $field: $field ?? this.$field,');
  }
  buffer
    ..writeln('      );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  AppColors lerp(ThemeExtension<AppColors>? other, double t) {')
    ..writeln('    if (other is! AppColors) return this;')
    ..writeln('    return AppColors(');
  for (final field in fields) {
    buffer.writeln('      $field: Color.lerp($field, other.$field, t)!,');
  }
  buffer
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

// ---------------------------------------------------------------------------
// Numeric scales
// ---------------------------------------------------------------------------

void _writeScale(
  StringBuffer buffer,
  String className,
  String label,
  Map<String, double> values,
) {
  final fields = values.keys.map(toLowerCamel).toList();

  buffer
    ..writeln('/// The $label scale.')
    ..writeln('///')
    ..writeln('/// Constant across modes, but still a [ThemeExtension] so that')
    ..writeln('/// a denser or larger variant can be swapped in for a subtree')
    ..writeln('/// without touching call sites.')
    ..writeln('@immutable')
    ..writeln('class $className extends ThemeExtension<$className> {')
    ..writeln('  const $className({');
  for (final field in fields) {
    buffer.writeln('    required this.$field,');
  }
  buffer
    ..writeln('  });')
    ..writeln();

  for (final field in fields) {
    buffer.writeln('  final double $field;');
  }
  buffer
    ..writeln()
    ..writeln('  static const $className tokens = $className(');
  for (final entry in values.entries) {
    buffer.writeln('    ${toLowerCamel(entry.key)}: ${_double(entry.value)},');
  }
  buffer
    ..writeln('  );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  $className copyWith({');
  for (final field in fields) {
    buffer.writeln('    double? $field,');
  }
  buffer
    ..writeln('  }) =>')
    ..writeln('      $className(');
  for (final field in fields) {
    buffer.writeln('        $field: $field ?? this.$field,');
  }
  buffer
    ..writeln('      );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  $className lerp(ThemeExtension<$className>? other, double t) {')
    ..writeln('    if (other is! $className) return this;')
    ..writeln('    return $className(');
  for (final field in fields) {
    buffer.writeln('      $field: lerpDouble($field, other.$field, t),');
  }
  buffer
    ..writeln('    );')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static double lerpDouble(double a, double b, double t) =>')
    ..writeln('      a + (b - a) * t;')
    ..writeln('}')
    ..writeln();
}

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

void _writeTypography(StringBuffer buffer, TokenSet tokens) {
  final fields = tokens.typography.map((t) => toLowerCamel(t.name)).toList();

  buffer
    ..writeln('/// Type scale.')
    ..writeln('///')
    ..writeln('/// Colour is deliberately absent from these styles: it comes')
    ..writeln('/// from the ColorScheme at use time, so one scale serves both')
    ..writeln('/// modes instead of being duplicated per mode.')
    ..writeln('@immutable')
    ..writeln('class AppTypography extends ThemeExtension<AppTypography> {')
    ..writeln('  const AppTypography({');
  for (final field in fields) {
    buffer.writeln('    required this.$field,');
  }
  buffer
    ..writeln('  });')
    ..writeln();

  for (final field in fields) {
    buffer.writeln('  final TextStyle $field;');
  }
  buffer
    ..writeln()
    ..writeln('  static const AppTypography tokens = AppTypography(');
  for (final token in tokens.typography) {
    buffer.writeln('    ${toLowerCamel(token.name)}: ${_textStyle(token, tokens.fontFamily)},');
  }
  buffer
    ..writeln('  );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  AppTypography copyWith({');
  for (final field in fields) {
    buffer.writeln('    TextStyle? $field,');
  }
  buffer
    ..writeln('  }) =>')
    ..writeln('      AppTypography(');
  for (final field in fields) {
    buffer.writeln('        $field: $field ?? this.$field,');
  }
  buffer
    ..writeln('      );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {')
    ..writeln('    if (other is! AppTypography) return this;')
    ..writeln('    return AppTypography(');
  for (final field in fields) {
    buffer.writeln('      $field: TextStyle.lerp($field, other.$field, t)!,');
  }
  buffer
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

String _textStyle(TypographyToken token, String? fontFamily) {
  final parts = <String>[
    if (fontFamily != null) "fontFamily: ${dartString(fontFamily)}",
    'fontSize: ${_double(token.size)}',
    'fontWeight: FontWeight.w${token.weight}',
    if (token.height != null) 'height: ${_double(token.height!)}',
    if (token.letterSpacing != null)
      'letterSpacing: ${_double(token.letterSpacing!)}',
  ];
  return 'TextStyle(${parts.join(', ')})';
}

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

void _writeTheme(StringBuffer buffer, TokenSet tokens) {
  final hasSpacing = tokens.spacing.isNotEmpty;
  final hasRadii = tokens.radii.isNotEmpty;
  final hasTypography = tokens.typography.isNotEmpty;

  buffer
    ..writeln('/// The generated themes. Pass to `MaterialApp`:')
    ..writeln('///')
    ..writeln('/// ```dart')
    ..writeln('/// MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark);')
    ..writeln('/// ```')
    ..writeln('class AppTheme {')
    ..writeln('  AppTheme._();')
    ..writeln()
    ..writeln('  static ThemeData get light =>')
    ..writeln('      _build(Brightness.light, AppColors.light);')
    ..writeln()
    ..writeln('  static ThemeData get dark =>')
    ..writeln('      _build(Brightness.dark, AppColors.dark);')
    ..writeln()
    ..writeln('  static ThemeData _build(Brightness brightness, AppColors colors) {')
    ..writeln('    final scheme = _colorScheme(brightness, colors);')
    ..writeln('    return ThemeData(')
    ..writeln('      useMaterial3: true,')
    ..writeln('      brightness: brightness,')
    ..writeln('      colorScheme: scheme,');
  if (tokens.fontFamily != null) {
    buffer.writeln('      fontFamily: ${dartString(tokens.fontFamily!)},');
  }
  if (hasTypography) {
    buffer.writeln('      textTheme: _textTheme(scheme.onSurface),');
  }
  buffer
    ..writeln('      extensions: <ThemeExtension<dynamic>>[')
    ..writeln('        colors,');
  if (hasSpacing) buffer.writeln('        AppSpacing.tokens,');
  if (hasRadii) buffer.writeln('        AppRadii.tokens,');
  if (hasTypography) buffer.writeln('        AppTypography.tokens,');
  buffer
    ..writeln('      ],')
    ..writeln('    );')
    ..writeln('  }')
    ..writeln();

  // ColorScheme.fromSeed fills the roles the token file does not name —
  // containers, inverse surfaces, scrims — with a harmonious palette derived
  // from the brand colour, then the named roles are pinned on top. Hand-
  // writing all ~30 Material roles in a token file is the alternative, and
  // nobody maintains it.
  buffer
    ..writeln('  /// Roles the token file names are pinned exactly; everything')
    ..writeln('  /// Material also needs (containers, inverse surfaces, scrims)')
    ..writeln('  /// is derived from the brand colour rather than demanding')
    ..writeln('  /// that the token file enumerate all thirty-odd roles.')
    ..writeln('  static ColorScheme _colorScheme(Brightness brightness, AppColors colors) =>')
    ..writeln('      ColorScheme.fromSeed(')
    ..writeln('        seedColor: colors.primary,')
    ..writeln('        brightness: brightness,')
    ..writeln('      ).copyWith(');
  for (final role in requiredColorRoles) {
    if (tokens.color(role) != null) {
      buffer.writeln('        ${toLowerCamel(role)}: colors.${toLowerCamel(role)},');
    }
  }
  for (final optional in ['outline', 'shadow', 'scrim', 'inverse_surface']) {
    if (tokens.color(optional) != null) {
      buffer.writeln('        ${toLowerCamel(optional)}: colors.${toLowerCamel(optional)},');
    }
  }
  buffer.writeln('      );');

  if (hasTypography) {
    final slots = tokens.typography
        .where((t) => _materialTextSlots.contains(t.name))
        .toList();
    buffer
      ..writeln()
      ..writeln('  /// Tokens named after a Material slot are wired into the')
      ..writeln('  /// TextTheme, so stock widgets pick them up without every')
      ..writeln('  /// call site reaching for AppTypography.')
      ..writeln('  static TextTheme _textTheme(Color color) => TextTheme(');
    for (final token in slots) {
      buffer.writeln(
          '        ${toLowerCamel(token.name)}: AppTypography.tokens.${toLowerCamel(token.name)}.copyWith(color: color),');
    }
    buffer.writeln('      );');
  }

  buffer
    ..writeln('}')
    ..writeln();
}

void _writeContextExtension(StringBuffer buffer, TokenSet tokens) {
  buffer
    ..writeln('/// `context.colors.primary` instead of')
    ..writeln('/// `Theme.of(context).extension<AppColors>()!.primary`.')
    ..writeln('extension AppThemeContext on BuildContext {')
    ..writeln('  AppColors get colors => Theme.of(this).extension<AppColors>()!;');
  if (tokens.spacing.isNotEmpty) {
    buffer.writeln('  AppSpacing get spacing => Theme.of(this).extension<AppSpacing>()!;');
  }
  if (tokens.radii.isNotEmpty) {
    buffer.writeln('  AppRadii get radii => Theme.of(this).extension<AppRadii>()!;');
  }
  if (tokens.typography.isNotEmpty) {
    buffer.writeln('  AppTypography get typography => Theme.of(this).extension<AppTypography>()!;');
  }
  buffer.writeln('}');
}

String _double(double value) =>
    value == value.roundToDouble() && value.abs() < 1e21
        ? value.toStringAsFixed(1)
        : '$value';
