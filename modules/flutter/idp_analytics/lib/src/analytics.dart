import 'dart:async';

import 'consent.dart';
import 'event.dart';
import 'sink.dart';
import 'validation.dart';

/// Signature for the error hook. Wire this to Crashlytics/Sentry so that a
/// permanently broken sink is visible; it is otherwise silent by design.
typedef AnalyticsErrorHandler = void Function(
  Object error,
  StackTrace stackTrace, {
  String? sinkId,
  String? operation,
});

/// The single entry point the app talks to.
///
/// Three properties are the point of this class, and all three are why call
/// sites should never touch a vendor SDK directly:
///
///  * **Fan-out.** Every sink receives every call. Adding Amplitude next to
///    Firebase is one line at composition, not a migration.
///  * **It never throws.** A vendor SDK that is uninitialised, offline or
///    mid-upgrade must not take a screen down with it. Failures go to
///    [AnalyticsErrorHandler]; one failing sink does not stop the others.
///  * **Consent is enforced here, once.** Not in each adapter, and not at each
///    call site, where it is guaranteed to be forgotten.
class Analytics {
  Analytics({
    required List<AnalyticsSink> sinks,
    Consent consent = Consent.unknown,
    AnalyticsErrorHandler? onError,
    int pendingLimit = 100,
  })  : _sinks = List.unmodifiable(sinks),
        _consent = consent,
        _onError = onError,
        _pendingLimit = pendingLimit {
    // Fire-and-forget: adapters are told the initial consent state so a vendor
    // with its own consent mode starts in the right one.
    unawaited(_forEachSink('setConsent', (s) => s.setConsent(_consent)));
  }

  /// An instance that does nothing. For unit tests and for flavors that must
  /// not report (a white-label build without a vendor account, say).
  factory Analytics.disabled() => Analytics(sinks: const []);

  final List<AnalyticsSink> _sinks;
  final AnalyticsErrorHandler? _onError;
  final int _pendingLimit;

  /// Work raised before consent resolved. Replayed on grant, dropped on deny.
  final List<_PendingOperation> _pending = [];

  Consent _consent;
  bool _disposed = false;
  int _droppedWhilePending = 0;

  Consent get consent => _consent;

  /// Number of operations discarded because the pre-consent buffer was full.
  /// Non-zero means something is logging in a loop before the consent prompt
  /// is answered; surface it in the debug panel rather than ignoring it.
  int get droppedWhilePending => _droppedWhilePending;

  List<String> get sinkIds => _sinks.map((s) => s.id).toList();

  // ---------------------------------------------------------------------------
  // Consent
  // ---------------------------------------------------------------------------

  /// Records the user's decision and releases or discards the buffer.
  ///
  /// Moving from granted back to denied calls [AnalyticsSink.reset] on every
  /// sink: withdrawal means the vendor should forget the identifiers it already
  /// holds, not merely stop receiving new ones.
  Future<void> setConsent(Consent consent) async {
    if (_disposed) return;
    final wasGranted = _consent.allowsAnalytics;
    _consent = consent;

    await _forEachSink('setConsent', (s) => s.setConsent(consent));

    if (consent.allowsAnalytics) {
      await _drainPending();
    } else {
      _pending.clear();
      if (wasGranted) {
        await _forEachSink('reset', (s) => s.reset());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  Future<void> log(AnalyticsEvent event) async {
    if (_disposed) return;

    final errors = validateParameters(event.parameters);
    if (errors.isNotEmpty) {
      // Reported, not thrown, and the event is still delivered without the bad
      // parameters: losing one field beats losing the event, and beats
      // crashing a release build over telemetry.
      _report(
        ArgumentError('Invalid parameters on "${event.name}": '
            '${errors.join('; ')}'),
        StackTrace.current,
        operation: 'log(${event.name})',
      );
    }

    final cleaned = sanitizeParameters(event.parameters);
    final safe = errors.isEmpty && identical(cleaned, event.parameters)
        ? event
        : RawEvent(event.name, {
            for (final e in cleaned.entries)
              if (e.value is String || e.value is num || e.value is bool)
                e.key: e.value,
          });

    return _dispatch('log(${safe.name})', (s) => s.logEvent(safe));
  }

  /// Ad-hoc event without a registry entry. Prefer a generated event.
  Future<void> logRaw(String name, [Map<String, Object?> parameters = const {}]) =>
      log(RawEvent(name, parameters));

  Future<void> logScreenView(String name, {String? className, Map<String, Object?> parameters = const {}}) =>
      _dispatch(
        'screen($name)',
        (s) => s.logScreenView(
          ScreenView(name, className: className, parameters: sanitizeParameters(parameters)),
        ),
      );

  Future<void> setUserId(String? userId) =>
      _dispatch('setUserId', (s) => s.setUserId(userId));

  Future<void> setUserProperty(String name, String? value) =>
      _dispatch('setUserProperty($name)', (s) => s.setUserProperty(name, value));

  /// Logout. Runs regardless of consent — clearing state must never be gated on
  /// a permission, or a denied user keeps the identifiers of a granted one.
  Future<void> reset() async {
    if (_disposed) return;
    _pending.clear();
    await _forEachSink('reset', (s) => s.reset());
  }

  Future<void> flush() async {
    if (_disposed) return;
    await _forEachSink('flush', (s) => s.flush());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    await _forEachSink('close', (s) => s.close());
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _dispatch(
    String operation,
    Future<void> Function(AnalyticsSink) action,
  ) async {
    if (_disposed) return;

    switch (_consent.analytics) {
      case ConsentStatus.granted:
        return _forEachSink(operation, action);
      case ConsentStatus.denied:
        return; // Silently dropped. The user said no.
      case ConsentStatus.unknown:
        if (_pending.length >= _pendingLimit) {
          // Keeps the oldest entries: the pre-consent window is the start of
          // the session, and the first events in it are the ones a funnel
          // needs. Overflow here means something is logging in a loop.
          _droppedWhilePending++;
          return;
        }
        _pending.add(_PendingOperation(operation, action));
    }
  }

  Future<void> _drainPending() async {
    if (_pending.isEmpty) return;
    final queued = List<_PendingOperation>.from(_pending);
    _pending.clear();
    for (final op in queued) {
      await _forEachSink(op.operation, op.action);
    }
  }

  /// Runs [action] against every sink, isolating failures. Sinks run
  /// concurrently — a slow vendor should not delay a fast one — but the
  /// returned future completes only when all have settled, so tests can await.
  Future<void> _forEachSink(
    String operation,
    Future<void> Function(AnalyticsSink) action,
  ) async {
    if (_sinks.isEmpty) return;
    await Future.wait(_sinks.map((sink) async {
      try {
        await action(sink);
      } catch (error, stack) {
        _report(error, stack, sinkId: sink.id, operation: operation);
      }
    }));
  }

  void _report(Object error, StackTrace stack, {String? sinkId, String? operation}) {
    final handler = _onError;
    if (handler == null) return;
    try {
      handler(error, stack, sinkId: sinkId, operation: operation);
    } catch (_) {
      // A throwing error handler must not become the thing that crashes.
    }
  }
}

class _PendingOperation {
  _PendingOperation(this.operation, this.action);

  final String operation;
  final Future<void> Function(AnalyticsSink) action;
}
