import '../diagnostics.dart';
import '../naming.dart';
import '../yaml_util.dart';
import 'model.dart';

/// Conditions a rule's `when` clause may use. Anything else is a typo, and a
/// typo that is silently ignored means a rollout quietly targets everybody.
const knownConditions = {
  'platform',
  'country',
  'locale',
  'user_id',
  'min_app_version',
  'max_app_version',
  'attributes',
};

/// Parses and validates `flags.yaml` in one pass.
///
/// Parsing and validation are together on purpose: separating them would mean
/// either a model that can hold invalid states or a parser that throws on the
/// first problem. Collecting diagnostics as it goes means one run reports every
/// bad flag rather than making the user fix them one at a time.
class FlagRegistryParser {
  FlagRegistryParser({this.environments = const ['dev', 'staging', 'prod']});

  final List<String> environments;

  final diagnostics = Diagnostics();

  FlagRegistry parse(String source, String path) {
    final doc = parseYamlDocument(source, path);
    final raw = doc['flags'];

    if (raw == null) {
      throw RegistryException('$path: missing top-level "flags:" list');
    }
    if (raw is! List<Object?>) {
      throw RegistryException('$path: "flags" must be a list');
    }

    final flags = <FlagDefinition>[];
    final seen = <String, int>{};

    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, Object?>) {
        diagnostics.error('each flag must be a mapping', location: 'flags[$i]');
        continue;
      }

      final key = entry['key'];
      if (key is! String || key.isEmpty) {
        diagnostics.error('missing required "key"', location: 'flags[$i]');
        continue;
      }

      final location = 'flags[$i] "$key"';

      if (seen.containsKey(key)) {
        diagnostics.error(
          'duplicate key, already defined at flags[${seen[key]}]',
          location: location,
        );
        continue;
      }
      seen[key] = i;

      final flag = _parseFlag(entry, key, location);
      if (flag != null) flags.add(flag);
    }

    return FlagRegistry(flags: flags, sourcePath: path);
  }

  FlagDefinition? _parseFlag(
    Map<String, Object?> entry,
    String key,
    String location,
  ) {
    if (!isSnakeCase(key)) {
      diagnostics.error(
        'key must be snake_case — it is used verbatim as the backend key',
        location: location,
      );
    }
    if (dartReservedWords.contains(toLowerCamel(key))) {
      diagnostics.error(
        '"${toLowerCamel(key)}" is a Dart keyword, so the generated constant '
        'would not compile; rename the flag',
        location: location,
      );
    }

    final type = FlagValueType.fromYaml(entry['type'] as String?);
    if (type == null) {
      diagnostics.error(
        'missing or unknown "type"; expected one of '
        '${FlagValueType.values.map((t) => t.yamlName).join(', ')}',
        location: location,
      );
      return null;
    }

    if (!entry.containsKey('default')) {
      diagnostics.error(
        'missing "default". It is compiled into the binary and is what users '
        'get before the first fetch and whenever the backend is unreachable, '
        'so it has to be stated explicitly.',
        location: location,
      );
      return null;
    }

    final defaultValue = _coerce(entry['default'], type, location, 'default');

    final allowedValues = _parseAllowedValues(entry, type, location);
    final min = _parseBound(entry, 'min', type, location);
    final max = _parseBound(entry, 'max', type, location);

    if (defaultValue != null) {
      _checkConstraints(defaultValue, allowedValues, min, max, location, 'default');
    }

    final owner = entry['owner'] as String?;
    if (owner == null || owner.isEmpty) {
      diagnostics.warning(
        'no "owner" — nobody is accountable for removing this flag',
        location: location,
      );
    }

    final description = entry['description'] as String?;
    if (description == null || description.isEmpty) {
      diagnostics.warning('no "description"', location: location);
    }

    final expires = _parseExpiry(entry['expires'], location);

    return FlagDefinition(
      key: key,
      type: type,
      defaultValue: defaultValue,
      description: description,
      owner: owner,
      expires: expires,
      allowedValues: allowedValues,
      min: min,
      max: max,
      environments: _parseEnvironments(entry, type, allowedValues, min, max, location),
    );
  }

  Map<String, FlagEnvironmentConfig> _parseEnvironments(
    Map<String, Object?> entry,
    FlagValueType type,
    List<String>? allowedValues,
    num? min,
    num? max,
    String location,
  ) {
    final raw = entry['environments'];
    if (raw == null) return const {};
    if (raw is! Map<String, Object?>) {
      diagnostics.error('"environments" must be a mapping', location: location);
      return const {};
    }

    final result = <String, FlagEnvironmentConfig>{};

    for (final env in raw.entries) {
      final envLocation = '$location environments.${env.key}';

      if (!environments.contains(env.key)) {
        diagnostics.error(
          'unknown environment "${env.key}"; expected one of '
          '${environments.join(', ')}',
          location: envLocation,
        );
        continue;
      }

      final value = env.value;

      // Shorthand: `prod: false` means that value with no targeting.
      if (value is! Map<String, Object?>) {
        final coerced = _coerce(value, type, envLocation, 'value');
        if (coerced != null) {
          _checkConstraints(coerced, allowedValues, min, max, envLocation, 'value');
        }
        result[env.key] = FlagEnvironmentConfig(value: coerced);
        continue;
      }

      if (!value.containsKey('value')) {
        diagnostics.error(
          'missing "value" — an environment block must state what everyone '
          'gets when no rule applies',
          location: envLocation,
        );
        continue;
      }

      final base = _coerce(value['value'], type, envLocation, 'value');
      if (base != null) {
        _checkConstraints(base, allowedValues, min, max, envLocation, 'value');
      }

      result[env.key] = FlagEnvironmentConfig(
        value: base,
        rules: _parseRules(value['rules'], type, allowedValues, min, max, envLocation),
      );
    }

    return result;
  }

  List<FlagRule> _parseRules(
    Object? raw,
    FlagValueType type,
    List<String>? allowedValues,
    num? min,
    num? max,
    String location,
  ) {
    if (raw == null) return const [];
    if (raw is! List<Object?>) {
      diagnostics.error('"rules" must be a list', location: location);
      return const [];
    }

    final rules = <FlagRule>[];

    for (var i = 0; i < raw.length; i++) {
      final ruleLocation = '$location rules[$i]';
      final entry = raw[i];

      if (entry is! Map<String, Object?>) {
        diagnostics.error('each rule must be a mapping', location: ruleLocation);
        continue;
      }
      if (!entry.containsKey('value')) {
        diagnostics.error('rule has no "value"', location: ruleLocation);
        continue;
      }

      final value = _coerce(entry['value'], type, ruleLocation, 'value');
      if (value != null) {
        _checkConstraints(value, allowedValues, min, max, ruleLocation, 'value');
      }

      final when = _parseWhen(entry['when'], ruleLocation);
      final rollout = entry['rollout'];
      double? percentage;
      String? seed;

      if (rollout != null) {
        if (rollout is! Map<String, Object?>) {
          diagnostics.error('"rollout" must be a mapping', location: ruleLocation);
        } else {
          final raw = rollout['percentage'];
          if (raw is! num) {
            diagnostics.error(
              '"rollout.percentage" must be a number between 0 and 100',
              location: ruleLocation,
            );
          } else if (raw < 0 || raw > 100) {
            diagnostics.error(
              'rollout percentage $raw is outside 0–100',
              location: ruleLocation,
            );
          } else {
            percentage = raw.toDouble();
          }
          seed = rollout['seed'] as String?;
        }
      }

      if (when.isEmpty && percentage == null) {
        diagnostics.warning(
          'rule has neither "when" nor "rollout", so it applies to everyone '
          'and makes every later rule unreachable — set the environment '
          '"value" instead',
          location: ruleLocation,
        );
      }

      rules.add(FlagRule(value: value, when: when, percentage: percentage, seed: seed));
    }

    return rules;
  }

  Map<String, Object?> _parseWhen(Object? raw, String location) {
    if (raw == null) return const {};
    if (raw is! Map<String, Object?>) {
      diagnostics.error('"when" must be a mapping', location: location);
      return const {};
    }
    for (final key in raw.keys) {
      if (!knownConditions.contains(key)) {
        diagnostics.error(
          'unknown condition "$key"; expected one of '
          '${knownConditions.join(', ')}. An ignored condition would make this '
          'rule target everyone.',
          location: location,
        );
      }
    }
    return raw;
  }

  DateTime? _parseExpiry(Object? raw, String location) {
    if (raw == null) {
      diagnostics.warning(
        'no "expires" — a flag with no removal date is how flag debt starts',
        location: location,
      );
      return null;
    }
    if (raw is DateTime) return DateTime.utc(raw.year, raw.month, raw.day);
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) {
      diagnostics.error(
        '"expires" must be a date like 2026-12-31',
        location: location,
      );
      return null;
    }
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  List<String>? _parseAllowedValues(
    Map<String, Object?> entry,
    FlagValueType type,
    String location,
  ) {
    final raw = entry['allowed_values'];
    if (raw == null) return null;
    if (type != FlagValueType.string) {
      diagnostics.error(
        '"allowed_values" applies only to string flags',
        location: location,
      );
      return null;
    }
    if (raw is! List<Object?>) {
      diagnostics.error('"allowed_values" must be a list', location: location);
      return null;
    }
    return raw.map((v) => v.toString()).toList();
  }

  num? _parseBound(
    Map<String, Object?> entry,
    String field,
    FlagValueType type,
    String location,
  ) {
    final raw = entry[field];
    if (raw == null) return null;
    if (type != FlagValueType.integer && type != FlagValueType.double) {
      diagnostics.error(
        '"$field" applies only to int and double flags',
        location: location,
      );
      return null;
    }
    if (raw is! num) {
      diagnostics.error('"$field" must be a number', location: location);
      return null;
    }
    return type == FlagValueType.integer ? raw.toInt() : raw.toDouble();
  }

  void _checkConstraints(
    Object value,
    List<String>? allowedValues,
    num? min,
    num? max,
    String location,
    String field,
  ) {
    if (allowedValues != null && value is String && !allowedValues.contains(value)) {
      diagnostics.error(
        '$field "$value" is not in allowed_values '
        '(${allowedValues.join(', ')}), so the app would reject it at runtime '
        'and fall back to the bundled default',
        location: location,
      );
    }
    if (value is num) {
      if (min != null && value < min) {
        diagnostics.error('$field $value is below min $min', location: location);
      }
      if (max != null && value > max) {
        diagnostics.error('$field $value is above max $max', location: location);
      }
    }
  }

  /// Checks a YAML value against the flag's declared type.
  ///
  /// Strict on purpose. YAML will happily give `"false"` where `false` was
  /// meant, and a string is truthy in enough places that the mistake survives
  /// to production; better to refuse it here.
  Object? _coerce(Object? value, FlagValueType type, String location, String field) {
    if (value == null) {
      diagnostics.error('$field may not be null', location: location);
      return null;
    }

    switch (type) {
      case FlagValueType.boolean:
        if (value is bool) return value;
      case FlagValueType.string:
        if (value is String) return value;
      case FlagValueType.integer:
        if (value is int) return value;
      case FlagValueType.double:
        if (value is num) return value.toDouble();
      case FlagValueType.json:
        if (value is Map<String, Object?>) return value;
    }

    diagnostics.error(
      '$field is ${value.runtimeType} but the flag is declared '
      '"${type.yamlName}"',
      location: location,
    );
    return null;
  }
}
