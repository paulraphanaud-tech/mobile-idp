/// An analytics event: a name plus a flat parameter map.
///
/// Implement this on a generated or hand-written class rather than calling
/// [Analytics.logRaw] everywhere — a typed event is greppable, renameable and
/// impossible to misspell at a call site. `idp_codegen` generates one class
/// per entry in `analytics/events.yaml`.
abstract class AnalyticsEvent {
  const AnalyticsEvent();

  String get name;

  /// Parameter values must be `String`, `num` or `bool`. Nested maps and lists
  /// are rejected by [Analytics] before they reach a sink, because no vendor
  /// accepts them uniformly and the failure is otherwise silent and per-vendor.
  Map<String, Object?> get parameters => const {};
}

/// Escape hatch for events that are not in the registry yet.
///
/// Deliberately more verbose than a generated event so that it stands out in
/// review. `make analytics-validate` reports call sites of this class.
class RawEvent extends AnalyticsEvent {
  const RawEvent(this.name, [this.parameters = const {}]);

  @override
  final String name;

  @override
  final Map<String, Object?> parameters;

  @override
  String toString() => 'RawEvent($name, $parameters)';
}

/// A screen view. Kept separate from [AnalyticsEvent] because most vendors
/// have a dedicated API for it that behaves differently from a custom event
/// (session stitching, automatic duration, funnel UI).
class ScreenView {
  const ScreenView(this.name, {this.className, this.parameters = const {}});

  final String name;
  final String? className;
  final Map<String, Object?> parameters;

  @override
  String toString() => 'ScreenView($name)';
}
