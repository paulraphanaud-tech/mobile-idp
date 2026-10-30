import '../consent.dart';
import '../event.dart';
import '../sink.dart';

/// Records everything in memory. For tests: assert on
/// `sink.events.map((e) => e.name)` instead of mocking a vendor SDK.
class MemoryAnalyticsSink extends AnalyticsSinkBase {
  MemoryAnalyticsSink({this.id = 'memory'});

  @override
  final String id;

  final List<AnalyticsEvent> events = [];
  final List<ScreenView> screens = [];
  final Map<String, String?> userProperties = {};
  final List<Consent> consentChanges = [];

  String? userId;
  int resetCount = 0;
  int flushCount = 0;

  @override
  Future<void> logEvent(AnalyticsEvent event) async => events.add(event);

  @override
  Future<void> logScreenView(ScreenView screen) async => screens.add(screen);

  @override
  Future<void> setUserId(String? userId) async => this.userId = userId;

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      userProperties[name] = value;

  @override
  Future<void> setConsent(Consent consent) async => consentChanges.add(consent);

  @override
  Future<void> reset() async {
    resetCount++;
    events.clear();
    screens.clear();
    userProperties.clear();
    userId = null;
  }

  @override
  Future<void> flush() async => flushCount++;

  /// Convenience for assertions.
  List<String> get eventNames => events.map((e) => e.name).toList();
}
