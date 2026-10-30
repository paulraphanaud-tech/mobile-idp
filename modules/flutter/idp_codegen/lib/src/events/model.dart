enum ParameterType {
  string('string', 'String'),
  integer('int', 'int'),
  double('double', 'double'),
  boolean('bool', 'bool');

  const ParameterType(this.yamlName, this.dartType);

  final String yamlName;
  final String dartType;

  static ParameterType? fromYaml(String? name) {
    for (final type in values) {
      if (type.yamlName == name) return type;
    }
    return null;
  }
}

class EventParameter {
  EventParameter({
    required this.name,
    required this.type,
    this.required = false,
    this.description,
    this.allowedValues,
  });

  final String name;
  final ParameterType type;
  final bool required;
  final String? description;
  final List<String>? allowedValues;
}

class EventDefinition {
  EventDefinition({
    required this.name,
    this.description,
    this.owner,
    this.parameters = const [],
  });

  final String name;
  final String? description;
  final String? owner;
  final List<EventParameter> parameters;
}

class EventRegistry {
  EventRegistry({required this.events, required this.sourcePath});

  final List<EventDefinition> events;
  final String sourcePath;
}
