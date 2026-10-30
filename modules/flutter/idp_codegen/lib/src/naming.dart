/// Naming rules shared by the flag and event registries.
///
/// Both are snake_case because that is what the backends store: Remote Config
/// keys, GA4 event names and BigQuery column names all end up in this shape,
/// and a camelCase key in the registry becomes a silent mismatch somewhere
/// downstream.
final _snakeCase = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

bool isSnakeCase(String value) => _snakeCase.hasMatch(value);

/// snake_case -> lowerCamelCase, for generated Dart identifiers.
String toLowerCamel(String value) {
  final parts = value.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return value;
  return parts.first + parts.skip(1).map(_capitalize).join();
}

/// snake_case -> UpperCamelCase, for generated Dart class names.
String toUpperCamel(String value) =>
    value.split('_').where((p) => p.isNotEmpty).map(_capitalize).join();

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Dart keywords that cannot be used as identifiers. A flag legitimately named
/// `switch` or `new` would otherwise generate code that does not compile, with
/// an error pointing at generated source rather than at the registry.
const dartReservedWords = {
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
  'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
  'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'for', 'function', 'get', 'hide',
  'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
  'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
  'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
};

/// Escapes a string for a single-quoted Dart literal.
String dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// Header written at the top of every generated file.
String generatedHeader(String source, String command) => '''
// GENERATED — DO NOT EDIT.
//
// Source:  $source
// Command: $command
//
// Edit the source registry and regenerate. Changes made here are lost on the
// next build, and CI fails when this file is out of date with its source.

// ignore_for_file: type=lint
''';
