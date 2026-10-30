import 'dart:convert';

import '../diagnostics.dart';
import 'model.dart';

const _encoder = JsonEncoder.withIndent('  ');

/// Renders the document `idp_feature_flags_aws` fetches from CloudFront.
///
/// Every flag in the registry gets an entry, including ones the environment
/// says nothing about — they fall back to the bundled default. An explicit
/// entry means the published document is a complete statement of what that
/// environment serves, so a diff against the previous version is meaningful.
String renderAwsDocument(
  FlagRegistry registry,
  String environment, {
  DateTime? publishedAt,
}) {
  final document = <String, Object?>{
    'schema': 1,
    'environment': environment,
    'published_at':
        (publishedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'flags': {
      for (final flag in registry.flags)
        flag.key: flag.configFor(environment).toDocumentJson(),
    },
  };
  return '${_encoder.convert(document)}\n';
}

/// Conditions the Firebase renderer can express.
///
/// Remote Config's condition language has no equivalent for a user allowlist
/// or a custom attribute unless the app also publishes them as Analytics user
/// properties, which is a different mechanism with its own propagation delay.
/// Rather than emit an expression that looks right and targets the wrong
/// people, those are rejected — the AWS backend evaluates them on device and
/// handles them exactly.
const firebaseSupportedConditions = {'platform', 'country'};

class RenderedFirebaseTemplate {
  RenderedFirebaseTemplate(this.json, this.diagnostics);

  final String json;
  final Diagnostics diagnostics;
}

/// Renders a Remote Config template for `firebase deploy --only remoteconfig`.
///
/// Remote Config stores every value as a string; `valueType` is what tells the
/// console and the SDK how to read it back.
RenderedFirebaseTemplate renderFirebaseTemplate(
  FlagRegistry registry,
  String environment,
) {
  final diagnostics = Diagnostics();
  final conditions = <Map<String, Object?>>[];
  final conditionNames = <String, String>{};
  final parameters = <String, Object?>{};

  for (final flag in registry.flags) {
    final config = flag.configFor(environment);
    final conditionalValues = <String, Object?>{};

    for (var i = 0; i < config.rules.length; i++) {
      final rule = config.rules[i];
      final expression = _expressionFor(
        flag,
        rule,
        environment,
        i,
        diagnostics,
      );
      if (expression == null) continue;

      // Identical expressions are shared. Remote Config caps the number of
      // conditions per project, and three flags rolling out to the same 25% of
      // iOS users should not burn three slots.
      final name = conditionNames.putIfAbsent(expression, () {
        final generated = 'idp_${flag.key}_$i';
        conditions.add({
          'name': generated,
          'expression': expression,
          'tagColor': 'BLUE',
        });
        return generated;
      });

      conditionalValues[name] = {'value': _asRemoteConfigString(rule.value)};
    }

    parameters[flag.key] = {
      'defaultValue': {'value': _asRemoteConfigString(config.value)},
      if (conditionalValues.isNotEmpty) 'conditionalValues': conditionalValues,
      if (flag.description != null && flag.description!.isNotEmpty)
        'description': flag.description,
      'valueType': _valueType(flag.type),
    };
  }

  final template = <String, Object?>{
    'conditions': conditions,
    'parameters': parameters,
    'parameterGroups': <String, Object?>{},
    'version': {
      'description': 'Published from flags.yaml for $environment by the IDP.',
    },
  };

  return RenderedFirebaseTemplate('${_encoder.convert(template)}\n', diagnostics);
}

String? _expressionFor(
  FlagDefinition flag,
  FlagRule rule,
  String environment,
  int index,
  Diagnostics diagnostics,
) {
  final location = 'flags "${flag.key}" environments.$environment rules[$index]';
  final clauses = <String>[];

  for (final entry in rule.when.entries) {
    if (!firebaseSupportedConditions.contains(entry.key)) {
      diagnostics.error(
        'the firebase backend cannot express the "${entry.key}" condition. '
        'Remote Config has no equivalent that targets the same people, so the '
        'rule is not translated rather than translated wrongly. Use the aws '
        'backend for this flag, or drop the condition.',
        location: location,
      );
      return null;
    }

    final values = _asList(entry.value);
    switch (entry.key) {
      case 'platform':
        clauses.add(values.length == 1
            ? "device.os == '${values.single.toLowerCase()}'"
            : 'device.os in [${values.map((v) => "'${v.toLowerCase()}'").join(', ')}]');
      case 'country':
        clauses.add(
            'device.country in [${values.map((v) => "'${v.toUpperCase()}'").join(', ')}]');
    }
  }

  final percentage = rule.percentage;
  if (percentage != null) {
    // Seeded per flag for the same reason the client bucketing is: two
    // independent 25% rollouts must not select the same quarter of users.
    final seed = rule.seed ?? flag.key;
    clauses.add("percent('$seed') <= $percentage");
  }

  if (clauses.isEmpty) return null;
  return clauses.join(' && ');
}

List<String> _asList(Object? value) => switch (value) {
      String s => [s],
      List<Object?> l => l.map((e) => e.toString()).toList(),
      null => const [],
      _ => [value.toString()],
    };

String _asRemoteConfigString(Object? value) => switch (value) {
      null => '',
      String s => s,
      bool b => b ? 'true' : 'false',
      Map<String, Object?> m => jsonEncode(m),
      List<Object?> l => jsonEncode(l),
      _ => value.toString(),
    };

String _valueType(FlagValueType type) => switch (type) {
      FlagValueType.boolean => 'BOOLEAN',
      FlagValueType.integer || FlagValueType.double => 'NUMBER',
      FlagValueType.json => 'JSON',
      FlagValueType.string => 'STRING',
    };
