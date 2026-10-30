import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:idp_feature_flags/idp_feature_flags.dart';

/// Firebase Remote Config binding for [FeatureFlags].
///
/// Remote Config stores every value as a string and hands back a
/// [RemoteConfigValue] that coerces on demand. This adapter uses the registry
/// it receives in [initialize] to coerce by the flag's *declared* type, so the
/// facade gets `true` rather than `"true"` and attribution stays meaningful.
class RemoteConfigFlagSource extends FlagSourceBase {
  RemoteConfigFlagSource({
    FirebaseRemoteConfig? remoteConfig,
    this.fetchTimeout = const Duration(seconds: 10),
    Duration? minimumFetchInterval,
    this.realtime = true,
  })  : _config = remoteConfig ?? FirebaseRemoteConfig.instance,
        _minimumFetchInterval =
            minimumFetchInterval ?? const Duration(hours: 1);

  final FirebaseRemoteConfig _config;
  final Duration fetchTimeout;
  final Duration _minimumFetchInterval;

  /// Subscribe to Remote Config realtime updates so a rollout reaches a running
  /// app without waiting for the next fetch window. Costs a persistent
  /// connection; turn it off if that matters more than propagation speed.
  final bool realtime;

  final _changes = StreamController<void>.broadcast();
  final _types = <String, FlagType>{};

  StreamSubscription<RemoteConfigUpdate>? _updates;

  @override
  String get id => 'remote_config';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> initialize(List<Flag<Object>> registry) async {
    for (final flag in registry) {
      _types[flag.key] = flag.type;
    }

    await _config.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: fetchTimeout,
      minimumFetchInterval: _minimumFetchInterval,
    ));

    // Registering defaults with the SDK is what makes getAll() report a
    // ValueSource for every known key. The facade applies its own defaults
    // anyway; these exist so `read` can tell "the backend said so" apart from
    // "nobody said anything", which is the difference between a real value and
    // a default wearing a disguise.
    await _config.setDefaults({
      for (final flag in registry) flag.key: _asDefault(flag),
    });

    if (realtime) {
      _updates = _config.onConfigUpdated.listen(
        (_) async {
          await _config.activate();
          if (!_changes.isClosed) _changes.add(null);
        },
        // Realtime is a nice-to-have; losing the stream must not break
        // fetch-based refresh.
        onError: (Object _) {},
      );
    }
  }

  @override
  Future<void> refresh() async {
    try {
      final activated = await _config.fetchAndActivate();
      if (activated && !_changes.isClosed) _changes.add(null);
    } on FirebaseException catch (_) {
      // Offline, throttled (minimumFetchInterval not elapsed), or the fetch
      // timed out. All three are ordinary: the previously activated values
      // stay in place and the facade keeps serving them. Swallowed rather than
      // rethrown so a flaky network is not reported as an error every hour.
    } on PlatformException catch (_) {
      // Same, for the platform-channel flavour of the above.
    }
  }

  @override
  Object? read(String key) {
    final value = _config.getValue(key);

    // `static` means Remote Config has never heard of this key. `defaultValue`
    // means it is echoing back what we registered in initialize(), not
    // something a human set in the backend. Both are "no opinion", so the
    // facade attributes the result to the bundled default rather than
    // reporting a remote value that nobody chose.
    if (value.source != ValueSource.valueRemote) return null;

    return switch (_types[key]) {
      FlagType.boolean => value.asBool(),
      FlagType.integer => value.asInt(),
      FlagType.double => value.asDouble(),
      // JSON arrives as a string; the facade's JsonFlag decodes it.
      FlagType.string || FlagType.json || null => value.asString(),
    };
  }

  @override
  Future<void> close() async {
    await _updates?.cancel();
    await _changes.close();
  }

  /// Remote Config defaults must be String, num or bool. A JSON flag's default
  /// is only ever compared against, never parsed, so an empty object is enough
  /// and avoids depending on the app's model being JSON-encodable.
  static Object _asDefault(Flag<Object> flag) => switch (flag.type) {
        FlagType.json => '{}',
        _ => flag.defaultValue,
      };
}
