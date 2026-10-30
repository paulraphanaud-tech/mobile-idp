import 'package:idp_analytics/idp_analytics.dart';
import 'package:test/test.dart';

class _Boom extends AnalyticsSinkBase {
  @override
  String get id => 'boom';

  @override
  Future<void> logEvent(AnalyticsEvent event) async => throw StateError('nope');
}

void main() {
  group('consent gating', () {
    test('buffers events raised before consent is answered', () async {
      final sink = MemoryAnalyticsSink();
      final analytics = Analytics(sinks: [sink]);

      await analytics.logRaw('app_open');
      expect(sink.eventNames, isEmpty, reason: 'nothing before consent');

      await analytics.setConsent(Consent.granted);
      expect(sink.eventNames, ['app_open'], reason: 'replayed on grant');
    });

    test('drops the buffer when consent is denied', () async {
      final sink = MemoryAnalyticsSink();
      final analytics = Analytics(sinks: [sink]);

      await analytics.logRaw('app_open');
      await analytics.setConsent(Consent.denied);

      expect(sink.eventNames, isEmpty);
      await analytics.logRaw('later');
      expect(sink.eventNames, isEmpty);
    });

    test('withdrawal resets sinks so identifiers are forgotten', () async {
      final sink = MemoryAnalyticsSink();
      final analytics = Analytics(sinks: [sink], consent: Consent.granted);

      await analytics.setUserId('u1');
      await analytics.setConsent(Consent.denied);

      expect(sink.resetCount, 1);
      expect(sink.userId, isNull);
    });

    test('keeps the oldest entries when the buffer overflows', () async {
      final sink = MemoryAnalyticsSink();
      final analytics = Analytics(sinks: [sink], pendingLimit: 2);

      await analytics.logRaw('first');
      await analytics.logRaw('second');
      await analytics.logRaw('third');
      await analytics.setConsent(Consent.granted);

      expect(sink.eventNames, ['first', 'second']);
      expect(analytics.droppedWhilePending, 1);
    });
  });

  group('fan-out', () {
    test('delivers to every sink', () async {
      final a = MemoryAnalyticsSink(id: 'a');
      final b = MemoryAnalyticsSink(id: 'b');
      final analytics =
          Analytics(sinks: [a, b], consent: Consent.granted);

      await analytics.logRaw('checkout_started', {'cart_value': 42});

      expect(a.eventNames, ['checkout_started']);
      expect(b.eventNames, ['checkout_started']);
    });

    test('one failing sink does not stop the others or throw', () async {
      final ok = MemoryAnalyticsSink();
      final errors = <String?>[];
      final analytics = Analytics(
        sinks: [_Boom(), ok],
        consent: Consent.granted,
        onError: (e, s, {sinkId, operation}) => errors.add(sinkId),
      );

      await analytics.logRaw('ping');

      expect(ok.eventNames, ['ping']);
      expect(errors, ['boom']);
    });
  });

  group('parameters', () {
    test('nulls are dropped rather than forwarded', () async {
      final sink = MemoryAnalyticsSink();
      final analytics = Analytics(sinks: [sink], consent: Consent.granted);

      await analytics.logRaw('e', {'kept': 1, 'gone': null});

      expect(sink.events.single.parameters, {'kept': 1});
    });

    test('unsupported types are reported and stripped, event still sent', () async {
      final sink = MemoryAnalyticsSink();
      final errors = <Object>[];
      final analytics = Analytics(
        sinks: [sink],
        consent: Consent.granted,
        onError: (e, s, {sinkId, operation}) => errors.add(e),
      );

      await analytics.logRaw('e', {'ok': 'yes', 'bad': {'nested': true}});

      expect(errors, hasLength(1));
      expect(sink.events.single.parameters, {'ok': 'yes'});
    });
  });

  test('disabled instance accepts calls and does nothing', () async {
    final analytics = Analytics.disabled();
    await analytics.setConsent(Consent.granted);
    await analytics.logRaw('anything');
    expect(analytics.sinkIds, isEmpty);
  });
}
