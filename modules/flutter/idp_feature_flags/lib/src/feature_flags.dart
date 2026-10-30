import 'dart:async';

import 'flag.dart';
import 'resolution.dart';
import 'source.dart';

/// Called the first time each flag is read with a given value.
///
/// Wire this to analytics to record **exposure** — which users actually saw
/// which variant. Without it an A/B test measures "who was bucketed", which
/// includes everyone who never reached the screen, and the result is noise.
///
/// Called at most once per flag-and-value per session, so it is safe to attach
/// even though flags are read inside `build()`.
typedef FlagExposureListener = void Function(FlagResolution<Object> resolution);

typedef FlagErrorHandler = void Function(
  Object error,
  StackTrace stackTrace, {
  String? sourceId,
  String? flagKey,
});

/// The single entry point the app talks to.
///
/// Resolution order, first match wins:
///
///   1. [FlagOverrideStore] — a developer or QA forcing a value on this device
///   2. each [FlagSource] in the order given — normally the remote backend
///   3. the flag's own [Flag.defaultValue], compiled into the binary
///
/// Reads are synchronous and never throw. A backend that is offline, throttled
/// or returning nonsense produces the bundled default, not an exception and not
/// a loading state.
class FeatureFlags {
  FeatureFlags({
    required List<Flag<Object>> registry,
    List<FlagSource> sources = const [],
    FlagOverrideStore? overrides,
    FlagExposureListener? onExposure,
    FlagErrorHandler? onError,
  })  : _registry = {for (final flag in registry) flag.key: flag},
        _overrides = overrides,
        _onExposure = onExposure,
        _onError = onError,
        // Overrides are a source like any other; putting them first is the
        // whole of "local beats remote".
        _sources = [if (overrides != null) overrides, ...sources] {
    _subscribe();
  }

  /// An instance backed by nothing but the bundled defaults. For tests and for
  /// builds that must not talk to a backend.
  factory FeatureFlags.defaults(List<Flag<Object>> registry) =>
      FeatureFlags(registry: registry);

  final Map<String, Flag<Object>> _registry;
  final List<FlagSource> _sources;
  final FlagOverrideStore? _overrides;
  final FlagExposureListener? _onExposure;
  final FlagErrorHandler? _onError;

  final _changes = StreamController<void>.broadcast();
  final _subscriptions = <StreamSubscription<void>>[];

  /// Guards against flooding: exposure fires once per flag-and-value, and each
  /// distinct decode failure is reported once rather than on every rebuild.
  final _exposed = <String>{};
  final _reported = <String>{};

  bool _initialized = false;
  bool _disposed = false;

  List<Flag<Object>> get registry => List.unmodifiable(_registry.values);

  FlagOverrideStore? get overrides => _overrides;

  /// Emits when any source's values change. Drive rebuilds from this — a
  /// `StreamBuilder` at the root, or whatever state management the app uses.
  Stream<void> get changes => _changes.stream;

  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Hands every source the registry, then does a first [refresh].
  ///
  /// Safe to `await` at startup, and equally safe not to: reads before this
  /// completes return bundled defaults rather than blocking. Blocking app start
  /// on a flag fetch trades a fast launch for a slow one on every cold start,
  /// which is rarely the right trade — hold the splash screen only for the
  /// handful of flags that change the first frame.
  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    _initialized = true;

    final flags = registry;
    for (final source in _sources) {
      await _guard(source.id, 'initialize', () => source.initialize(flags));
    }
    await refresh();
  }

  /// Pulls new values from every source. Call on resume and after login.
  Future<void> refresh() async {
    if (_disposed) return;
    await Future.wait(
      _sources.map((s) => _guard(s.id, 'refresh', s.refresh)),
    );
    _emitChange();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final source in _sources) {
      await _guard(source.id, 'close', source.close);
    }
    await _changes.close();
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// The value of [flag]. Synchronous, never throws.
  T value<T extends Object>(Flag<T> flag) => resolve(flag).value;

  /// Shorthand for boolean flags.
  bool isEnabled(BoolFlag flag) => value(flag);

  /// Full evaluation including attribution. Used by the debug panel; use
  /// [value] at ordinary call sites.
  FlagResolution<T> resolve<T extends Object>(Flag<T> flag) {
    _warnIfUnregistered(flag);

    for (final source in _sources) {
      Object? raw;
      try {
        raw = source.read(flag.key);
      } catch (error, stack) {
        // read() is documented not to do I/O and not to throw, but a buggy
        // adapter must not be able to break a build().
        _report(error, stack, sourceId: source.id, flagKey: flag.key);
        continue;
      }
      if (raw == null) continue;

      final decoded = flag.decode(raw);
      if (decoded == null) {
        _reportOnce(
          'decode:${source.id}:${flag.key}:$raw',
          FormatException(
            'Source "${source.id}" returned $raw for flag "${flag.key}", which '
            'is not a valid ${flag.type.name}. Using the bundled default '
            '(${flag.defaultValue}).',
          ),
          flagKey: flag.key,
          sourceId: source.id,
        );
        return _expose(FlagResolution(
          flag: flag,
          value: flag.defaultValue,
          sourceId: null,
          raw: raw,
          decodeFailed: true,
        ));
      }

      return _expose(FlagResolution(
        flag: flag,
        value: decoded,
        sourceId: source.id,
        raw: raw,
      ));
    }

    return _expose(FlagResolution(
      flag: flag,
      value: flag.defaultValue,
      sourceId: null,
      raw: null,
    ));
  }

  /// Every flag's current resolution. For the debug panel and for attaching a
  /// flag snapshot to a crash report.
  List<FlagResolution<Object>> resolveAll() =>
      [for (final flag in _registry.values) resolve(flag)];

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _subscribe() {
    for (final source in _sources) {
      try {
        _subscriptions.add(source.changes.listen(
          (_) => _emitChange(),
          onError: (Object error, StackTrace stack) =>
              _report(error, stack, sourceId: source.id),
        ));
      } catch (error, stack) {
        _report(error, stack, sourceId: source.id);
      }
    }
  }

  void _emitChange() {
    // Values may differ now, so exposure is allowed to fire again — otherwise
    // a mid-session rollout is never recorded.
    _exposed.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  FlagResolution<T> _expose<T extends Object>(FlagResolution<T> resolution) {
    final listener = _onExposure;
    if (listener == null) return resolution;

    if (!_exposed.add('${resolution.flag.key}=${resolution.value}')) {
      return resolution;
    }
    try {
      listener(resolution as FlagResolution<Object>);
    } catch (error, stack) {
      _report(error, stack, flagKey: resolution.flag.key);
    }
    return resolution;
  }

  void _warnIfUnregistered(Flag<Object> flag) {
    if (_registry.containsKey(flag.key)) return;
    _reportOnce(
      'unregistered:${flag.key}',
      StateError(
        'Flag "${flag.key}" was read but is not in the registry passed to '
        'FeatureFlags. It will always resolve to its default, because sources '
        'were never told to fetch it.',
      ),
      flagKey: flag.key,
    );
  }

  Future<void> _guard(
    String sourceId,
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stack) {
      _report(error, stack, sourceId: sourceId, flagKey: null);
    }
  }

  void _reportOnce(
    String dedupeKey,
    Object error, {
    String? sourceId,
    String? flagKey,
  }) {
    if (!_reported.add(dedupeKey)) return;
    _report(error, StackTrace.current, sourceId: sourceId, flagKey: flagKey);
  }

  void _report(
    Object error,
    StackTrace stack, {
    String? sourceId,
    String? flagKey,
  }) {
    final handler = _onError;
    if (handler == null) return;
    try {
      handler(error, stack, sourceId: sourceId, flagKey: flagKey);
    } catch (_) {
      // A throwing error handler must not become the thing that crashes.
    }
  }
}
