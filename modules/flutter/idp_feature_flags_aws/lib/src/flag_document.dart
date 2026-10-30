import 'dart:convert';

import 'evaluation_context.dart';
import 'targeting.dart';

/// One flag as published: an environment-wide value plus ordered targeting
/// rules that can override it for a subset of users.
class FlagEntry {
  const FlagEntry({required this.value, this.rules = const []});

  /// What everyone gets when no rule applies.
  final Object? value;

  /// Evaluated in order; the first that applies wins.
  final List<TargetingRule> rules;

  static FlagEntry fromJson(Object? json) {
    // A bare scalar is shorthand for "this value, no targeting" — which is
    // what most flags are, and writing `{"value": true}` for all of them makes
    // the document tedious to read in review.
    if (json is! Map<String, Object?>) return FlagEntry(value: json);

    return FlagEntry(
      value: json['value'],
      rules: (json['rules'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(TargetingRule.fromJson)
          .toList(),
    );
  }

  Object? evaluate(String key, EvaluationContext context) {
    for (final rule in rules) {
      final result = rule.evaluate(key, context);
      if (result != null) return result;
    }
    return value;
  }
}

/// The published flag document for one environment.
///
/// Generated from `flags/flags.yaml` by `make flags-publish` and served from
/// S3 through CloudFront. The app never talks to the AWS control plane — it
/// does a plain cacheable HTTPS GET, so there are no AWS credentials in the
/// binary and no per-device API cost.
class FlagDocument {
  const FlagDocument({
    required this.flags,
    this.schema = 1,
    this.environment,
    this.publishedAt,
  });

  static const supportedSchema = 1;

  final int schema;
  final String? environment;
  final DateTime? publishedAt;
  final Map<String, FlagEntry> flags;

  /// Throws [FormatException] on anything it cannot read. Callers treat that
  /// as "keep the previous document" rather than surfacing it to the user.
  static FlagDocument parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('flag document is not valid JSON: ${e.message}');
    }

    if (decoded is! Map<String, Object?>) {
      throw const FormatException('flag document must be a JSON object');
    }

    final schema = (decoded['schema'] as num?)?.toInt() ?? supportedSchema;
    if (schema > supportedSchema) {
      // Forward incompatibility is a real scenario: the platform publishes a
      // newer document while old app versions are still installed. Refusing it
      // keeps those clients on their last-known-good rather than having them
      // misread a format they do not understand.
      throw FormatException(
        'flag document schema $schema is newer than this client supports '
        '($supportedSchema); keeping the previous document',
      );
    }

    final raw = decoded['flags'];
    if (raw is! Map<String, Object?>) {
      throw const FormatException('flag document has no "flags" object');
    }

    return FlagDocument(
      schema: schema,
      environment: decoded['environment'] as String?,
      publishedAt: DateTime.tryParse(decoded['published_at'] as String? ?? ''),
      flags: {
        for (final entry in raw.entries) entry.key: FlagEntry.fromJson(entry.value),
      },
    );
  }

  /// Null means this document says nothing about [key], so the facade moves on
  /// to the next source and then the bundled default.
  Object? evaluate(String key, EvaluationContext context) =>
      flags[key]?.evaluate(key, context);

  @override
  String toString() => 'FlagDocument(${flags.length} flags, '
      'environment: $environment, publishedAt: $publishedAt)';
}
