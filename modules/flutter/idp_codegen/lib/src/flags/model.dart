/// The value types a flag may declare. Mirrors `FlagType` in
/// `idp_feature_flags`; kept separate so the tool does not depend on the
/// runtime package.
enum FlagValueType {
  boolean('bool', 'BoolFlag', 'bool'),
  string('string', 'StringFlag', 'String'),
  integer('int', 'IntFlag', 'int'),
  double('double', 'DoubleFlag', 'double'),
  json('json', 'JsonFlag', 'Map<String, Object?>');

  const FlagValueType(this.yamlName, this.dartClass, this.dartType);

  /// How it is spelled in `flags.yaml`.
  final String yamlName;
  final String dartClass;
  final String dartType;

  static FlagValueType? fromYaml(String? name) {
    for (final type in values) {
      if (type.yamlName == name) return type;
    }
    return null;
  }
}

/// One targeting rule as written in the registry.
class FlagRule {
  FlagRule({
    required this.value,
    this.when = const {},
    this.percentage,
    this.seed,
  });

  final Object? value;
  final Map<String, Object?> when;
  final double? percentage;
  final String? seed;

  Map<String, Object?> toDocumentJson() => {
        if (when.isNotEmpty) 'when': when,
        if (percentage != null)
          'rollout': {
            'percentage': percentage,
            if (seed != null) 'seed': seed,
          },
        'value': value,
      };
}

/// What one environment publishes for a flag.
class FlagEnvironmentConfig {
  FlagEnvironmentConfig({required this.value, this.rules = const []});

  final Object? value;
  final List<FlagRule> rules;

  Object? toDocumentJson() {
    // A flag with no targeting is emitted as a bare scalar. Most flags are
    // this, and spelling them all out as objects makes the published document
    // tedious to read in review.
    if (rules.isEmpty) return value;
    return {
      'value': value,
      'rules': [for (final rule in rules) rule.toDocumentJson()],
    };
  }
}

class FlagDefinition {
  FlagDefinition({
    required this.key,
    required this.type,
    required this.defaultValue,
    this.description,
    this.owner,
    this.expires,
    this.allowedValues,
    this.min,
    this.max,
    this.environments = const {},
  });

  final String key;
  final FlagValueType type;

  /// Compiled into the binary. Used before the first fetch, when the backend
  /// is unreachable, and when a published value fails to decode.
  final Object? defaultValue;

  final String? description;
  final String? owner;

  /// The date this flag should be gone. Drives `make flags-audit`.
  final DateTime? expires;

  final List<String>? allowedValues;
  final num? min;
  final num? max;

  final Map<String, FlagEnvironmentConfig> environments;

  bool get isExpired =>
      expires != null && expires!.isBefore(DateTime.now().toUtc());

  /// What [environment] publishes, falling back to the bundled default so that
  /// an environment which says nothing still gets an explicit entry in the
  /// document rather than a hole.
  FlagEnvironmentConfig configFor(String environment) =>
      environments[environment] ?? FlagEnvironmentConfig(value: defaultValue);
}

class FlagRegistry {
  FlagRegistry({required this.flags, required this.sourcePath});

  final List<FlagDefinition> flags;
  final String sourcePath;
}
