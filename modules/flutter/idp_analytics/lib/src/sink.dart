import 'consent.dart';
import 'event.dart';

/// A destination for analytics. One per vendor.
///
/// Adding a vendor means adding a package that implements this interface and
/// passing an instance to [Analytics] — no call site in the app changes. Extend
/// [AnalyticsSinkBase] rather than implementing this directly, so that methods
/// added here in a later version do not break existing adapters.
abstract class AnalyticsSink {
  /// Stable identifier, used in error reports and by [Analytics.only].
  String get id;

  Future<void> logEvent(AnalyticsEvent event);

  Future<void> logScreenView(ScreenView screen);

  Future<void> setUserId(String? userId);

  Future<void> setUserProperty(String name, String? value);

  /// Called on every consent change, including the initial value.
  ///
  /// Sinks that can run in a reduced mode (Firebase's consent mode, for
  /// instance) should honour this. [Analytics] already withholds events while
  /// consent is not granted, so a sink that cannot do anything useful here may
  /// ignore it.
  Future<void> setConsent(Consent consent);

  /// Forget everything about the current user. Called on logout and on consent
  /// withdrawal.
  Future<void> reset();

  /// Push anything buffered in the vendor SDK. Best-effort.
  Future<void> flush();

  /// Release resources. Called by [Analytics.dispose].
  Future<void> close();
}

/// No-op implementation of every member, so an adapter overrides only what its
/// vendor actually supports.
abstract class AnalyticsSinkBase implements AnalyticsSink {
  const AnalyticsSinkBase();

  @override
  Future<void> logEvent(AnalyticsEvent event) async {}

  @override
  Future<void> logScreenView(ScreenView screen) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setUserProperty(String name, String? value) async {}

  @override
  Future<void> setConsent(Consent consent) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
