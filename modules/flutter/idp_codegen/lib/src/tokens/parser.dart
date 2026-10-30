import 'dart:convert';

import '../diagnostics.dart';
import '../naming.dart';
import 'model.dart';

/// Reads `design/tokens.json`.
///
/// JSON rather than YAML because this is the file a design tool writes:
/// Figma's Token Studio, Style Dictionary and every other exporter emit JSON,
/// so keeping the format means an export can be dropped in without a
/// conversion step in between.
class TokenParser {
  final diagnostics = Diagnostics();

  TokenSet parse(String source, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw RegistryException('$path: not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw RegistryException('$path: expected a JSON object at the top level');
    }

    final colors = _parseColors(decoded['color']);

    for (final role in requiredColorRoles) {
      if (colors.every((c) => c.name != role)) {
        diagnostics.error(
          'missing required colour role "$role". Without it the generated '
          'ColorScheme is incomplete and stock Material widgets keep their '
          'default colours.',
          location: 'color',
        );
      }
    }

    return TokenSet(
      sourcePath: path,
      colors: colors,
      spacing: _parseScale(decoded['spacing'], 'spacing'),
      radii: _parseScale(decoded['radius'], 'radius'),
      typography: _parseTypography(decoded['typography']),
      fontFamily: (decoded['font'] as Map<String, Object?>?)?['family'] as String?,
    );
  }

  List<ColorToken> _parseColors(Object? raw) {
    if (raw == null) {
      diagnostics.error('missing "color" section');
      return const [];
    }
    if (raw is! Map<String, Object?>) {
      diagnostics.error('"color" must be an object');
      return const [];
    }

    final tokens = <ColorToken>[];

    for (final entry in raw.entries) {
      final location = 'color.${entry.key}';

      if (!isSnakeCase(entry.key)) {
        diagnostics.error(
          'token names must be snake_case (generated as '
          '"${toLowerCamel(entry.key)}")',
          location: location,
        );
      }

      final value = entry.value;

      // A bare string means the colour is the same in both modes — true for
      // brand colours and for anything that is deliberately not themed.
      if (value is String) {
        final parsed = _parseHex(value, location);
        if (parsed != null) {
          tokens.add(ColorToken(name: entry.key, light: parsed, dark: parsed));
        }
        continue;
      }

      if (value is! Map<String, Object?>) {
        diagnostics.error(
          'must be a hex string or an object with "light" and "dark"',
          location: location,
        );
        continue;
      }

      final light = _parseHex(value['light'], '$location.light');
      final dark = _parseHex(value['dark'], '$location.dark');

      if (light == null || dark == null) continue;
      tokens.add(ColorToken(name: entry.key, light: light, dark: dark));
    }

    return tokens;
  }

  int? _parseHex(Object? raw, String location) {
    if (raw is! String) {
      diagnostics.error('expected a hex colour string', location: location);
      return null;
    }

    var hex = raw.trim();
    if (!hex.startsWith('#')) {
      diagnostics.error('colour must start with "#"', location: location);
      return null;
    }
    hex = hex.substring(1);

    // #RGB shorthand, as CSS and every design tool allow.
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'FF$hex'; // Opaque unless told otherwise.

    if (hex.length != 8) {
      diagnostics.error(
        'expected #RGB, #RRGGBB or #AARRGGBB, got "$raw"',
        location: location,
      );
      return null;
    }

    final value = int.tryParse(hex, radix: 16);
    if (value == null) {
      diagnostics.error('"$raw" is not a valid hex colour', location: location);
      return null;
    }
    return value;
  }

  Map<String, double> _parseScale(Object? raw, String section) {
    if (raw == null) return const {};
    if (raw is! Map<String, Object?>) {
      diagnostics.error('"$section" must be an object');
      return const {};
    }

    final result = <String, double>{};

    for (final entry in raw.entries) {
      final location = '$section.${entry.key}';
      if (!isSnakeCase(entry.key)) {
        diagnostics.error('scale steps must be snake_case', location: location);
      }
      final value = entry.value;
      if (value is! num) {
        diagnostics.error('expected a number', location: location);
        continue;
      }
      if (value < 0) {
        diagnostics.error('may not be negative', location: location);
        continue;
      }
      result[entry.key] = value.toDouble();
    }

    return result;
  }

  List<TypographyToken> _parseTypography(Object? raw) {
    if (raw == null) return const [];
    if (raw is! Map<String, Object?>) {
      diagnostics.error('"typography" must be an object');
      return const [];
    }

    final tokens = <TypographyToken>[];

    for (final entry in raw.entries) {
      final location = 'typography.${entry.key}';
      final value = entry.value;

      if (value is! Map<String, Object?>) {
        diagnostics.error('must be an object with at least "size"', location: location);
        continue;
      }

      final size = value['size'];
      if (size is! num) {
        diagnostics.error('missing numeric "size"', location: location);
        continue;
      }

      final weight = value['weight'] ?? 400;
      if (weight is! num || weight < 100 || weight > 900 || weight % 100 != 0) {
        diagnostics.error(
          '"weight" must be a multiple of 100 between 100 and 900',
          location: location,
        );
        continue;
      }

      final height = value['height'];
      if (height != null && height is num && height > 10) {
        // The usual export mistake: a design tool writes line height in
        // pixels, Flutter wants a multiplier. Caught here because the result
        // is a layout that is technically valid and visibly wrong.
        diagnostics.warning(
          '"height" is $height. Flutter treats it as a multiple of font size, '
          'so this line will be $height× ${size}px tall. If the design tool '
          'exported pixels, divide by the font size.',
          location: location,
        );
      }

      tokens.add(TypographyToken(
        name: entry.key,
        size: size.toDouble(),
        weight: weight.toInt(),
        height: (height as num?)?.toDouble(),
        letterSpacing: (value['letter_spacing'] as num?)?.toDouble(),
      ));
    }

    return tokens;
  }
}
