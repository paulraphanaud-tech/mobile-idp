import 'dart:async';

import 'flag.dart';

/// A place flag values come from. One per backend.
///
/// Sources are consulted **synchronously** by `FeatureFlags.value`, because
/// flags are read inside `build()` and an async read there turns every flagged
/// widget into a FutureBuilder with a loading state. A source therefore keeps
/// its own in-memory snapshot, updates it during [refresh], and serves [read]
/// from that snapshot without doing I/O.
abstract class FlagSource {
  /// Stable identifier. Appears in `FlagResolution.sourceId` and in the debug
  /// panel, so "why is this flag on?" has an answer.
  String get id;

  /// Called once with the full registry before the first [refresh].
  ///
  /// Sources use this to register in-binary defaults with the backend SDK and
  /// to learn each flag's [FlagType], which backends that store everything as
  /// text need in order to hand back a usefully typed value.
  Future<void> initialize(List<Flag<Object>> registry);

  /// Fetches new values into the snapshot.
  ///
  /// Must not throw for ordinary failures — offline, timeout, throttled.
  /// Those leave the previous snapshot in place and return normally. Throw
  /// only for genuine bugs.
  Future<void> refresh();

  /// Reads from the snapshot. Null means "no opinion": the next source is
  /// consulted, and then the flag's default.
  Object? read(String key);

  /// Emits when [read] would return something different. Drives UI rebuilds.
  Stream<void> get changes;

  Future<void> close();
}

/// Everything except [id] and [read] defaulted, so an adapter implements only
/// what its backend needs.
abstract class FlagSourceBase implements FlagSource {
  const FlagSourceBase();

  @override
  Future<void> initialize(List<Flag<Object>> registry) async {}

  @override
  Future<void> refresh() async {}

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> close() async {}
}

/// Values fixed at construction. Useful as a bundled-defaults layer, and the
/// easiest way to pin flags in a test.
class StaticFlagSource extends FlagSourceBase {
  StaticFlagSource(this.values, {this.id = 'static'});

  final Map<String, Object?> values;

  @override
  final String id;

  @override
  Object? read(String key) => values[key];
}

/// Developer and QA overrides.
///
/// Consulted **before** every remote source, so a tester can force a flag on
/// one device without touching the backend and without affecting anyone else.
///
/// In-memory by default. To survive a restart, pass [persist] backed by
/// SharedPreferences — or whatever the project already uses — rather than
/// pulling a storage dependency into this package.
class FlagOverrideStore implements FlagSource {
  FlagOverrideStore({
    Map<String, Object?>? initial,
    Future<void> Function(Map<String, Object?> overrides)? persist,
    this.enabled = true,
  })  : _overrides = {...?initial},
        _persist = persist;

  final Map<String, Object?> _overrides;
  final Future<void> Function(Map<String, Object?>)? _persist;
  final _controller = StreamController<void>.broadcast();

  /// Set false in release builds. When disabled the store has no opinion at
  /// all, so an override left behind by a developer cannot ship to users.
  final bool enabled;

  @override
  String get id => 'override';

  Map<String, Object?> get overrides => Map.unmodifiable(_overrides);

  bool get isEmpty => _overrides.isEmpty;

  @override
  Object? read(String key) => enabled ? _overrides[key] : null;

  Future<void> set(String key, Object? value) => _mutate(() => _overrides[key] = value);

  Future<void> clear(String key) => _mutate(() => _overrides.remove(key));

  Future<void> clearAll() => _mutate(_overrides.clear);

  Future<void> _mutate(void Function() change) async {
    change();
    if (!_controller.isClosed) _controller.add(null);
    await _persist?.call(Map.of(_overrides));
  }

  @override
  Future<void> initialize(List<Flag<Object>> registry) async {}

  @override
  Future<void> refresh() async {}

  @override
  Stream<void> get changes => _controller.stream;

  @override
  Future<void> close() async => _controller.close();
}
