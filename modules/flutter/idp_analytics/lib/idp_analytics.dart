/// Vendor-neutral analytics for IDP-bootstrapped Flutter apps.
///
/// The app depends on this package only. Vendors arrive as separate packages
/// implementing [AnalyticsSink] — see `idp_analytics_firebase` for a worked
/// example of what a second one looks like.
library;

export 'src/analytics.dart';
export 'src/consent.dart';
export 'src/event.dart';
export 'src/sink.dart';
export 'src/sinks/console_sink.dart';
export 'src/sinks/memory_sink.dart';
export 'src/validation.dart' show ParameterError, validateParameters;
