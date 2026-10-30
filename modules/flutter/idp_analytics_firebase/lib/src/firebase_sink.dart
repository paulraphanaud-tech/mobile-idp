import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:idp_analytics/idp_analytics.dart';

/// Firebase Analytics (GA4) binding for [Analytics].
///
/// This is the platform's worked example of a vendor adapter: everything
/// vendor-specific lives here, and adding Amplitude or PostHog later means
/// writing a sibling of this file, not touching the app.
///
/// GA4 constraints this adapter enforces, because Firebase applies them
/// silently and a truncated or rejected event is otherwise invisible until
/// someone notices a dashboard is wrong weeks later:
///
///  * event names: <= 40 characters, and the `firebase_` / `google_` / `ga_`
///    prefixes are reserved — such events are **dropped** and reported, since
///    the SDK would reject them anyway
///  * parameter names: <= 40 characters
///  * string parameter values: <= 100 characters, truncated here
///  * <= 25 parameters per event
///
/// `idp_codegen validate` checks the same rules at build time; these runtime
/// checks catch `logRaw` call sites that bypass the registry.
class FirebaseAnalyticsSink extends AnalyticsSinkBase {
  FirebaseAnalyticsSink({
    FirebaseAnalytics? analytics,
    this.onDropped,
  }) : _analytics = analytics ?? FirebaseAnalytics.instance;

  static const _reservedPrefixes = ['firebase_', 'google_', 'ga_'];
  static const _maxNameLength = 40;
  static const _maxStringValueLength = 100;
  static const _maxParameters = 25;

  final FirebaseAnalytics _analytics;

  /// Called when this adapter refuses an event GA4 would have rejected.
  /// Wire it to your error reporter; silence here is how dashboards rot.
  final void Function(String eventName, String reason)? onDropped;

  @override
  String get id => 'firebase';

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    final rejection = _rejectionReason(event.name);
    if (rejection != null) {
      onDropped?.call(event.name, rejection);
      return;
    }
    await _analytics.logEvent(
      name: event.name,
      parameters: _coerce(event.parameters, event.name),
    );
  }

  @override
  Future<void> logScreenView(ScreenView screen) => _analytics.logScreenView(
        screenName: screen.name,
        screenClass: screen.className,
        parameters: _coerce(screen.parameters, 'screen_view'),
      );

  @override
  Future<void> setUserId(String? userId) => _analytics.setUserId(id: userId);

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _analytics.setUserProperty(name: name, value: value);

  /// Maps the facade's consent onto Firebase consent mode, and additionally
  /// stops collection outright when analytics consent is not granted.
  ///
  /// Both are needed. Consent mode alone still lets the SDK send cookieless
  /// pings; `setAnalyticsCollectionEnabled(false)` is what actually stops
  /// traffic. `Analytics` already withholds events, so this is defence in
  /// depth against anything reaching the SDK by another path — automatic
  /// screen tracking, say.
  @override
  Future<void> setConsent(Consent consent) async {
    final analyticsGranted = consent.allowsAnalytics;
    final marketingGranted = consent.marketing == ConsentStatus.granted;

    await _analytics.setConsent(
      analyticsStorageConsentGranted: analyticsGranted,
      adStorageConsentGranted: marketingGranted,
      adUserDataConsentGranted: marketingGranted,
      adPersonalizationSignalsConsentGranted: marketingGranted,
    );
    await _analytics.setAnalyticsCollectionEnabled(analyticsGranted);
  }

  @override
  Future<void> reset() => _analytics.resetAnalyticsData();

  // Firebase Analytics has no flush API — the SDK batches on its own schedule
  // (roughly hourly, or immediately in DebugView). Left as the inherited no-op
  // rather than faked, so nobody writes a test that depends on it.

  String? _rejectionReason(String name) {
    if (name.length > _maxNameLength) {
      return 'event name is ${name.length} characters; GA4 allows $_maxNameLength';
    }
    for (final prefix in _reservedPrefixes) {
      if (name.startsWith(prefix)) {
        return 'event name uses the reserved prefix "$prefix"';
      }
    }
    return null;
  }

  Map<String, Object>? _coerce(Map<String, Object?> parameters, String eventName) {
    if (parameters.isEmpty) return null;

    final out = <String, Object>{};
    for (final entry in parameters.entries) {
      final value = entry.value;
      if (value == null) continue;

      if (out.length >= _maxParameters) {
        onDropped?.call(
          eventName,
          'more than $_maxParameters parameters; "${entry.key}" and any after '
          'it were dropped',
        );
        break;
      }

      final key = entry.key.length > _maxNameLength
          ? entry.key.substring(0, _maxNameLength)
          : entry.key;

      if (value is String && value.length > _maxStringValueLength) {
        out[key] = value.substring(0, _maxStringValueLength);
      } else if (value is String || value is num) {
        out[key] = value;
      } else if (value is bool) {
        // GA4 has no boolean parameter type. Sent as 1/0 rather than "true"/
        // "false" so the field stays numeric and can be averaged in BigQuery.
        out[key] = value ? 1 : 0;
      }
    }
    return out.isEmpty ? null : out;
  }
}
