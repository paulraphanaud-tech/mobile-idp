/// Who is asking. Rules in the flag document are matched against this.
///
/// [stableId] is the only required field and it carries the most weight: it is
/// what percentage rollouts bucket on, so it must be **stable across launches**
/// or a user will flip in and out of an experiment between sessions and the
/// results will be meaningless. A persisted install id is right; a per-session
/// uuid is not. It does not need to be a user id, and for GDPR reasons usually
/// should not be.
class EvaluationContext {
  const EvaluationContext({
    required this.stableId,
    this.userId,
    this.platform,
    this.appVersion,
    this.locale,
    this.country,
    this.attributes = const {},
  });

  final String stableId;
  final String? userId;

  /// 'ios' | 'android' — matched case-insensitively against a rule's platform.
  final String? platform;

  /// Semantic version of the app, e.g. '2.1.0'. Compared numerically by
  /// segment, so '2.10.0' is correctly newer than '2.9.0'.
  final String? appVersion;

  final String? locale;
  final String? country;

  /// Anything else a rule might match on: plan tier, tenant, opt-in flags.
  /// Values should be String, num or bool.
  final Map<String, Object?> attributes;

  Object? operator [](String key) => switch (key) {
        'stable_id' => stableId,
        'user_id' => userId,
        'platform' => platform,
        'app_version' => appVersion,
        'locale' => locale,
        'country' => country,
        _ => attributes[key],
      };

  EvaluationContext copyWith({
    String? stableId,
    String? userId,
    String? platform,
    String? appVersion,
    String? locale,
    String? country,
    Map<String, Object?>? attributes,
  }) =>
      EvaluationContext(
        stableId: stableId ?? this.stableId,
        userId: userId ?? this.userId,
        platform: platform ?? this.platform,
        appVersion: appVersion ?? this.appVersion,
        locale: locale ?? this.locale,
        country: country ?? this.country,
        attributes: attributes ?? this.attributes,
      );

  @override
  String toString() => 'EvaluationContext(stableId: $stableId, '
      'platform: $platform, appVersion: $appVersion)';
}
