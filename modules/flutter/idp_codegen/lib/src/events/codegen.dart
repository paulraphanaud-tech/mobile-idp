import '../naming.dart';
import 'model.dart';

/// Emits one class per registered event.
///
/// A typed event is the difference between an analytics implementation that
/// can be refactored and one that cannot: the name exists once, renaming it is
/// a compile error at every call site, and a required parameter cannot be
/// forgotten. `logRaw` remains available for the genuinely ad-hoc case, and
/// deliberately looks worse at the call site.
String generateEventsDart(EventRegistry registry, {String? command}) {
  final buffer = StringBuffer()
    ..write(generatedHeader(
      registry.sourcePath,
      command ?? 'make analytics-codegen',
    ))
    ..writeln()
    ..writeln("import 'package:idp_analytics/idp_analytics.dart';")
    ..writeln();

  for (final event in registry.events) {
    _writeEvent(buffer, event);
  }

  buffer
    ..writeln('/// Every registered event name, for tests that assert on the')
    ..writeln('/// registry and for a debug screen that lists what the app can')
    ..writeln('/// emit.')
    ..writeln('class Events {')
    ..writeln('  Events._();')
    ..writeln()
    ..writeln('  static const List<String> names = <String>[');
  for (final event in registry.events) {
    buffer.writeln('    ${dartString(event.name)},');
  }
  buffer
    ..writeln('  ];')
    ..writeln('}');

  return buffer.toString();
}

void _writeEvent(StringBuffer buffer, EventDefinition event) {
  final className = toUpperCamel(event.name);

  if (event.description != null) buffer.writeln('/// ${event.description}');
  if (event.owner != null) {
    if (event.description != null) buffer.writeln('///');
    buffer.writeln('/// Owner: ${event.owner}');
  }

  buffer.writeln('class $className extends AnalyticsEvent {');

  if (event.parameters.isEmpty) {
    buffer
      ..writeln('  const $className();')
      ..writeln();
  } else {
    buffer.writeln('  const $className({');
    for (final parameter in event.parameters) {
      final field = toLowerCamel(parameter.name);
      buffer.writeln(
          '    ${parameter.required ? 'required ' : ''}this.$field,');
    }
    buffer
      ..writeln('  });')
      ..writeln();

    for (final parameter in event.parameters) {
      final doc = <String>[
        if (parameter.description != null) parameter.description!,
        if (parameter.allowedValues != null)
          'One of: ${parameter.allowedValues!.join(', ')}.',
      ];
      for (final line in doc) {
        buffer.writeln('  /// $line');
      }
      final type =
          parameter.required ? parameter.type.dartType : '${parameter.type.dartType}?';
      buffer.writeln('  final $type ${toLowerCamel(parameter.name)};');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('  @override')
    ..writeln('  String get name => ${dartString(event.name)};')
    ..writeln();

  if (event.parameters.isEmpty) {
    buffer
      ..writeln('  @override')
      ..writeln('  Map<String, Object?> get parameters => const {};');
  } else {
    buffer
      ..writeln('  @override')
      ..writeln('  Map<String, Object?> get parameters => <String, Object?>{');
    for (final parameter in event.parameters) {
      final field = toLowerCamel(parameter.name);
      // Optional parameters are omitted rather than sent as null: vendors
      // disagree about what a null means, and some store the string "null".
      buffer.writeln(parameter.required
          ? '    ${dartString(parameter.name)}: $field,'
          : '    if ($field != null) ${dartString(parameter.name)}: $field,');
    }
    buffer.writeln('  };');
  }

  buffer
    ..writeln('}')
    ..writeln();
}
