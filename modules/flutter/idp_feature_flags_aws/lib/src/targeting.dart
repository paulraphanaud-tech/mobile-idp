import 'evaluation_context.dart';

/// Deterministic bucketing for percentage rollouts.
///
/// FNV-1a over `"<seed>:<stableId>"`. Three properties matter and all three
/// are load-bearing:
///
///  * **Stable.** The same device always lands in the same bucket, so a user
///    does not flip in and out of an experiment between launches.
///  * **Per-flag.** The seed defaults to the flag key, so two independent
///    flags at 25% do not select the *same* quarter of users. Sharing a bucket
///    across flags silently correlates experiments and makes their results
///    uninterpretable. Set an explicit shared seed only when you actually want
///    mutually exclusive or aligned cohorts.
///  * **Client-side.** No round trip, so it works offline and on the very
///    first frame.
///
/// Returns a value in [0, 100).
double bucketOf(String seed, String stableId) {
  const offsetBasis = 0x811c9dc5;
  const prime = 0x01000193;

  var hash = offsetBasis;
  for (final unit in '$seed:$stableId'.codeUnits) {
    hash ^= unit;
    // Keep it inside 32 bits; Dart ints are 64-bit and would otherwise drift
    // from the reference FNV-1a, breaking cross-implementation agreement.
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  // 10_000 slots rather than 100, so a 0.5% rollout is expressible.
  return (hash % 10000) / 100.0;
}

/// Compares dotted numeric versions: '2.10.0' is newer than '2.9.0'.
///
/// Any pre-release or build suffix ('2.1.0-beta.3', '2.1.0+42') is ignored —
/// the comparison is about which release a user is on, and a build number is
/// not something a rollout rule should hinge on.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();

  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// The `when` clause of a rule. Every condition present must match (AND).
/// An empty condition set matches everyone.
class RuleConditions {
  const RuleConditions({
    this.platforms,
    this.countries,
    this.locales,
    this.userIds,
    this.minAppVersion,
    this.maxAppVersion,
    this.attributes = const {},
  });

  final List<String>? platforms;
  final List<String>? countries;
  final List<String>? locales;

  /// Allowlist. The practical way to switch a feature on for the internal
  /// team before anyone else sees it.
  final List<String>? userIds;

  final String? minAppVersion;
  final String? maxAppVersion;

  /// Custom attribute matches: key -> acceptable values.
  final Map<String, List<Object?>> attributes;

  static RuleConditions fromJson(Map<String, Object?> json) => RuleConditions(
        platforms: _stringList(json['platform']),
        countries: _stringList(json['country']),
        locales: _stringList(json['locale']),
        userIds: _stringList(json['user_id']),
        minAppVersion: json['min_app_version'] as String?,
        maxAppVersion: json['max_app_version'] as String?,
        attributes: {
          for (final entry
              in (json['attributes'] as Map<String, Object?>? ?? const {})
                  .entries)
            entry.key: entry.value is List
                ? (entry.value! as List).cast<Object?>()
                : [entry.value],
        },
      );

  bool matches(EvaluationContext context) {
    if (!_matchesCaseInsensitive(platforms, context.platform)) return false;
    if (!_matchesCaseInsensitive(countries, context.country)) return false;
    if (!_matchesCaseInsensitive(locales, context.locale)) return false;
    if (userIds != null && !userIds!.contains(context.userId)) return false;

    final version = context.appVersion;
    if (minAppVersion != null) {
      // No version in the context means the rule cannot be satisfied. Failing
      // closed is deliberate: a version-gated rollout must not reach clients
      // whose version is unknown.
      if (version == null) return false;
      if (compareVersions(version, minAppVersion!) < 0) return false;
    }
    if (maxAppVersion != null) {
      if (version == null) return false;
      if (compareVersions(version, maxAppVersion!) > 0) return false;
    }

    for (final entry in attributes.entries) {
      if (!entry.value.contains(context[entry.key])) return false;
    }
    return true;
  }

  static bool _matchesCaseInsensitive(List<String>? allowed, String? actual) {
    if (allowed == null) return true;
    if (actual == null) return false;
    final lower = actual.toLowerCase();
    return allowed.any((v) => v.toLowerCase() == lower);
  }

  static List<String>? _stringList(Object? value) => switch (value) {
        null => null,
        String s => [s],
        List<Object?> l => l.map((e) => e.toString()).toList(),
        _ => null,
      };
}

/// One targeting rule: who it applies to, and what they get.
class TargetingRule {
  const TargetingRule({
    required this.value,
    this.conditions = const RuleConditions(),
    this.percentage,
    this.seed,
  });

  final Object? value;
  final RuleConditions conditions;

  /// Share of matching users who get [value], 0–100. Null means all of them.
  final double? percentage;

  /// Bucketing seed. Defaults to the flag key — see [bucketOf].
  final String? seed;

  static TargetingRule fromJson(Map<String, Object?> json) {
    final rollout = json['rollout'] as Map<String, Object?>?;
    return TargetingRule(
      value: json['value'],
      conditions: RuleConditions.fromJson(
          json['when'] as Map<String, Object?>? ?? const {}),
      percentage: (rollout?['percentage'] as num?)?.toDouble(),
      seed: rollout?['seed'] as String?,
    );
  }

  /// Null when the rule does not apply — either its conditions did not match,
  /// or they did but this user fell outside the rollout percentage. Both cases
  /// fall through to the next rule.
  Object? evaluate(String flagKey, EvaluationContext context) {
    if (!conditions.matches(context)) return null;
    final share = percentage;
    if (share == null) return value;
    if (share >= 100) return value;
    if (share <= 0) return null;
    return bucketOf(seed ?? flagKey, context.stableId) < share ? value : null;
  }
}
