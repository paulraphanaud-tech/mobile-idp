import '../naming.dart';
import 'model.dart';

/// Emits the typed flag constants the app reads.
///
/// Generating these is what makes a flag key impossible to misspell at a call
/// site, makes a rename a compile error instead of a silent always-default,
/// and lets `FeatureFlags` be handed a registry that provably matches the one
/// published to the backend.
String generateFlagsDart(FlagRegistry registry, {String? command}) {
  final buffer = StringBuffer()
    ..write(generatedHeader(
      registry.sourcePath,
      command ?? 'make flags-codegen',
    ))
    ..writeln()
    ..writeln("import 'package:idp_feature_flags/idp_feature_flags.dart';")
    ..writeln()
    ..writeln('/// Every flag declared in `${registry.sourcePath}`.')
    ..writeln('class Flags {')
    ..writeln('  Flags._();')
    ..writeln();

  for (final flag in registry.flags) {
    _writeFlag(buffer, flag);
  }

  buffer
    ..writeln('  /// Pass to `FeatureFlags(registry: Flags.all)`.')
    ..writeln('  ///')
    ..writeln('  /// A flag missing from this list always resolves to its')
    ..writeln('  /// default, because sources are never told to fetch it.')
    ..writeln('  static const List<Flag<Object>> all = <Flag<Object>>[');

  for (final flag in registry.flags) {
    buffer.writeln('    ${toLowerCamel(flag.key)},');
  }

  buffer
    ..writeln('  ];')
    ..writeln('}');

  if (registry.flags.any((f) => f.type == FlagValueType.json)) {
    buffer
      ..writeln()
      ..writeln('/// JSON flags are handed back unparsed. Wrap one in your own')
      ..writeln('/// `JsonFlag` with a real `parse` if you want a typed model.')
      ..writeln('Map<String, Object?>? _asJson(Map<String, Object?> json) => json;');
  }

  return buffer.toString();
}

void _writeFlag(StringBuffer buffer, FlagDefinition flag) {
  final doc = <String>[
    if (flag.description != null && flag.description!.isNotEmpty)
      flag.description!,
  ];

  final meta = <String>[
    if (flag.owner != null) 'Owner: ${flag.owner}',
    if (flag.expires != null)
      'Expires: ${flag.expires!.toIso8601String().split('T').first}'
          '${flag.isExpired ? ' (PAST DUE — remove this flag)' : ''}',
  ];

  for (final line in doc) {
    buffer.writeln('  /// $line');
  }
  if (doc.isNotEmpty && meta.isNotEmpty) buffer.writeln('  ///');
  if (meta.isNotEmpty) buffer.writeln('  /// ${meta.join(' · ')}');

  final name = toLowerCamel(flag.key);
  final isJson = flag.type == FlagValueType.json;
  final className =
      isJson ? 'JsonFlag<Map<String, Object?>>' : flag.type.dartClass;

  buffer
    ..writeln('  static const $name = $className(')
    ..writeln("    key: ${dartString(flag.key)},")
    ..writeln('    defaultValue: ${dartLiteral(flag.defaultValue)},');

  if (isJson) buffer.writeln('    parse: _asJson,');

  if (flag.description != null && flag.description!.isNotEmpty) {
    buffer.writeln('    description: ${dartString(flag.description!)},');
  }
  if (flag.owner != null && flag.owner!.isNotEmpty) {
    buffer.writeln('    owner: ${dartString(flag.owner!)},');
  }
  if (flag.allowedValues != null) {
    final values = flag.allowedValues!.map(dartString).join(', ');
    buffer.writeln('    allowedValues: <String>[$values],');
  }
  if (flag.min != null) buffer.writeln('    min: ${dartLiteral(flag.min)},');
  if (flag.max != null) buffer.writeln('    max: ${dartLiteral(flag.max)},');

  buffer
    ..writeln('  );')
    ..writeln();
}

/// Renders a value as a Dart literal valid in a `const` context.
String dartLiteral(Object? value) {
  if (value == null) return 'null';
  if (value is String) return dartString(value);
  if (value is bool) return '$value';
  if (value is int) return '$value';
  if (value is double) {
    // `1` is an int literal and will not type-check as a double parameter.
    return value == value.roundToDouble() && value.abs() < 1e21
        ? value.toStringAsFixed(1)
        : '$value';
  }
  if (value is Map) {
    final entries = value.entries
        .map((e) => '${dartString(e.key.toString())}: ${dartLiteral(e.value)}')
        .join(', ');
    return '<String, Object?>{$entries}';
  }
  if (value is List) {
    return '<Object?>[${value.map(dartLiteral).join(', ')}]';
  }
  return dartString(value.toString());
}
