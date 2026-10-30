import 'package:flutter/widgets.dart';
import 'package:idp_analytics/idp_analytics.dart';

/// Makes [Analytics] available to the widget tree.
///
/// Provided for apps with no DI container. If the project already uses
/// Riverpod, get_it or provider, use that instead — this exists so that
/// "how do I reach analytics from a widget?" has an answer on day one and
/// nobody reaches for a global singleton.
class AnalyticsScope extends InheritedWidget {
  const AnalyticsScope({
    required this.analytics,
    required super.child,
    super.key,
  });

  final Analytics analytics;

  /// Throws if absent — a missing scope is a wiring bug, and returning a
  /// silent no-op would hide it until someone asks why the funnel is empty.
  static Analytics of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AnalyticsScope>();
    assert(scope != null, 'No AnalyticsScope found above this widget.');
    return scope!.analytics;
  }

  /// Null-returning variant, for widgets that are legitimately used both
  /// inside and outside an instrumented tree.
  static Analytics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnalyticsScope>()?.analytics;

  @override
  bool updateShouldNotify(AnalyticsScope oldWidget) =>
      !identical(analytics, oldWidget.analytics);
}
