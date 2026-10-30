import 'package:yaml/yaml.dart';

import 'diagnostics.dart';

/// Converts YAML nodes into plain Dart collections.
///
/// `YamlMap` implements `Map` but is not a `Map<String, Object?>`, so every
/// downstream cast fails in a way that reads like a type-system puzzle rather
/// than "your registry is malformed". Normalising once at the boundary keeps
/// the rest of the tool working with ordinary maps and lists.
Object? normalizeYaml(Object? node) {
  if (node is YamlMap) {
    return <String, Object?>{
      for (final entry in node.nodes.entries)
        entry.key.toString(): normalizeYaml(entry.value),
    };
  }
  if (node is YamlList) {
    return node.nodes.map(normalizeYaml).toList();
  }
  if (node is YamlScalar) return node.value;
  if (node is Map) {
    return <String, Object?>{
      for (final entry in node.entries)
        entry.key.toString(): normalizeYaml(entry.value),
    };
  }
  if (node is List) return node.map(normalizeYaml).toList();
  return node;
}

Map<String, Object?> parseYamlDocument(String source, String path) {
  final Object? doc;
  try {
    doc = normalizeYaml(loadYaml(source));
  } on YamlException catch (e) {
    throw RegistryException('$path: $e');
  }
  if (doc == null) throw RegistryException('$path: file is empty');
  if (doc is! Map<String, Object?>) {
    throw RegistryException('$path: expected a mapping at the top level');
  }
  return doc;
}
