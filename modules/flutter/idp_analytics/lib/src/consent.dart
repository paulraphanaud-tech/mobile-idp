/// Whether the user has answered the consent prompt, and how.
///
/// [unknown] is the state before the user has been asked. It is not the same
/// as [denied]: events raised while unknown are buffered and replayed if
/// consent is later granted, whereas events raised while denied are dropped.
/// Collapsing the two loses every event that happens during app start, which
/// is usually the most interesting part of a first session.
enum ConsentStatus { unknown, granted, denied }

/// Consent split by purpose. Analytics and marketing are separate because
/// most consent UIs (and the GDPR/ePrivacy reading behind them) let a user
/// accept one and refuse the other.
class Consent {
  const Consent({
    this.analytics = ConsentStatus.unknown,
    this.marketing = ConsentStatus.unknown,
  });

  static const unknown = Consent();
  static const granted =
      Consent(analytics: ConsentStatus.granted, marketing: ConsentStatus.granted);
  static const denied =
      Consent(analytics: ConsentStatus.denied, marketing: ConsentStatus.denied);

  /// Consent for analytics only — the common outcome of a two-toggle prompt.
  static const analyticsOnly =
      Consent(analytics: ConsentStatus.granted, marketing: ConsentStatus.denied);

  final ConsentStatus analytics;
  final ConsentStatus marketing;

  bool get allowsAnalytics => analytics == ConsentStatus.granted;
  bool get isResolved => analytics != ConsentStatus.unknown;

  Consent copyWith({ConsentStatus? analytics, ConsentStatus? marketing}) =>
      Consent(
        analytics: analytics ?? this.analytics,
        marketing: marketing ?? this.marketing,
      );

  @override
  String toString() => 'Consent(analytics: ${analytics.name}, marketing: ${marketing.name})';
}
