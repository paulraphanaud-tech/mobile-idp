import 'package:flutter/widgets.dart';
import 'package:idp_analytics/idp_analytics.dart';

/// Reports screen views from Navigator 1.0 route changes.
///
/// Vendor-neutral on purpose: it calls [Analytics.logScreenView], so every
/// configured sink receives the screen view. Firebase's own
/// `FirebaseAnalyticsObserver` would report to Firebase alone, which silently
/// gives you a second vendor with no screen data.
///
/// ```dart
/// MaterialApp(navigatorObservers: [AnalyticsNavigatorObserver(analytics)]);
/// ```
///
/// With go_router, pass it via `GoRouter(observers: [...])`.
class AnalyticsNavigatorObserver extends RouteObserver<ModalRoute<void>> {
  AnalyticsNavigatorObserver(
    this._analytics, {
    this.nameExtractor = defaultNameExtractor,
  });

  final Analytics _analytics;

  /// Returns the screen name for a route, or null to skip it.
  ///
  /// Skipping matters: the default extractor ignores routes with no name,
  /// which is what dialogs, bottom sheets and anonymous `MaterialPageRoute`s
  /// usually are. Reporting those as screens inflates screen counts and
  /// corrupts per-screen engagement time.
  final String? Function(Route<dynamic> route) nameExtractor;

  static String? defaultNameExtractor(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return null;
    return name;
  }

  void _report(Route<dynamic>? route) {
    if (route == null) return;
    final name = nameExtractor(route);
    if (name == null) return;
    // Fire-and-forget: Analytics never throws, and a navigation must not wait
    // on a vendor SDK.
    _analytics.logScreenView(name, className: route.runtimeType.toString());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _report(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _report(newRoute);
  }

  /// On pop the user lands back on the route underneath, which is a new screen
  /// view for them even though nothing was pushed.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _report(previousRoute);
  }
}
