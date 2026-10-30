import 'dart:async';

import 'package:idp_feature_flags/idp_feature_flags.dart';
import 'package:test/test.dart';

const newCheckout = BoolFlag(key: 'new_checkout', defaultValue: false);
const maxRetries = IntFlag(key: 'max_retries', defaultValue: 3, min: 0, max: 10);
const theme = StringFlag(
  key: 'theme',
  defaultValue: 'light',
  allowedValues: ['light', 'dark'],
);

final registry = <Flag<Object>>[newCheckout, maxRetries, theme];

class _MutableSource extends FlagSourceBase {
  _MutableSource(this.values, {this.id = 'remote'});

  final Map<String, Object?> values;
  final _controller = StreamController<void>.broadcast();

  @override
  final String id;

  int refreshCount = 0;

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> refresh() async => refreshCount++;

  @override
  Stream<void> get changes => _controller.stream;

  void push(String key, Object? value) {
    values[key] = value;
    _controller.add(null);
  }

  @override
  Future<void> close() async => _controller.close();
}

class _BrokenSource extends FlagSourceBase {
  @override
  String get id => 'broken';

  @override
  Object? read(String key) => throw StateError('read exploded');

  @override
  Future<void> refresh() async => throw StateError('refresh exploded');
}

void main() {
  group('resolution order', () {
    test('falls back to the bundled default when nothing has an opinion', () {
      final flags = FeatureFlags.defaults(registry);

      expect(flags.isEnabled(newCheckout), isFalse);
      expect(flags.resolve(newCheckout).isDefault, isTrue);
    });

    test('a source beats the default', () {
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'new_checkout': true})],
      );

      expect(flags.isEnabled(newCheckout), isTrue);
      expect(flags.resolve(newCheckout).sourceId, 'remote');
    });

    test('a local override beats the source', () async {
      final overrides = FlagOverrideStore();
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'theme': 'dark'})],
        overrides: overrides,
      );
      expect(flags.value(theme), 'dark');

      await overrides.set('theme', 'light');

      final resolution = flags.resolve(theme);
      expect(resolution.value, 'light');
      expect(resolution.isOverridden, isTrue);
    });

    test('a disabled override store has no opinion at all', () async {
      final overrides = FlagOverrideStore(enabled: false);
      await overrides.set('theme', 'light');

      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'theme': 'dark'})],
        overrides: overrides,
      );

      expect(flags.value(theme), 'dark');
    });

    test('earlier sources win over later ones', () {
      final flags = FeatureFlags(
        registry: registry,
        sources: [
          _MutableSource({}, id: 'first'),
          _MutableSource({'max_retries': 7}, id: 'second'),
        ],
      );

      // A null read is "no opinion", so the second source is consulted.
      expect(flags.value(maxRetries), 7);
      expect(flags.resolve(maxRetries).sourceId, 'second');
    });
  });

  group('decoding', () {
    test('coerces the strings a text-only backend returns', () {
      final flags = FeatureFlags(
        registry: registry,
        sources: [
          _MutableSource({'new_checkout': 'true', 'max_retries': '5'}),
        ],
      );

      expect(flags.isEnabled(newCheckout), isTrue);
      expect(flags.value(maxRetries), 5);
    });

    test('an undecodable value degrades to the default and is reported', () {
      final errors = <Object>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'max_retries': 'not-a-number'})],
        onError: (e, s, {sourceId, flagKey}) => errors.add(e),
      );

      final resolution = flags.resolve(maxRetries);
      expect(resolution.value, 3);
      expect(resolution.decodeFailed, isTrue);
      expect(errors, hasLength(1));
    });

    test('a value outside allowedValues is rejected', () {
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'theme': 'sepia'})],
      );

      expect(flags.value(theme), 'light');
      expect(flags.resolve(theme).decodeFailed, isTrue);
    });

    test('a value outside min/max is rejected', () {
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'max_retries': 99})],
      );

      expect(flags.value(maxRetries), 3);
    });

    test('repeated reads report the same failure once', () {
      final errors = <Object>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'max_retries': 'bad'})],
        onError: (e, s, {sourceId, flagKey}) => errors.add(e),
      );

      for (var i = 0; i < 50; i++) {
        flags.value(maxRetries);
      }

      expect(errors, hasLength(1), reason: 'build() runs constantly');
    });
  });

  group('exposure', () {
    test('fires once per flag and value, not once per read', () {
      final exposures = <String>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'new_checkout': true})],
        onExposure: (r) => exposures.add('${r.flag.key}=${r.value}'),
      );

      for (var i = 0; i < 10; i++) {
        flags.isEnabled(newCheckout);
      }

      expect(exposures, ['new_checkout=true']);
    });

    test('fires again after values change mid-session', () async {
      final source = _MutableSource({'theme': 'light'});
      final exposures = <String>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [source],
        onExposure: (r) => exposures.add('${r.flag.key}=${r.value}'),
      );

      flags.value(theme);
      source.push('theme', 'dark');
      await Future<void>.delayed(Duration.zero);
      flags.value(theme);

      expect(exposures, ['theme=light', 'theme=dark']);
    });

    test('carries attribution', () {
      FlagResolution<Object>? seen;
      FeatureFlags(
        registry: registry,
        sources: [_MutableSource({'new_checkout': true})],
        onExposure: (r) => seen = r,
      ).isEnabled(newCheckout);

      expect(seen!.sourceId, 'remote');
      expect(seen!.isDefault, isFalse);
      expect(seen!.raw, true);
    });
  });

  group('robustness', () {
    test('a source that throws on read is skipped, not fatal', () {
      final errors = <Object>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [_BrokenSource(), _MutableSource({'new_checkout': true})],
        onError: (e, s, {sourceId, flagKey}) => errors.add(e),
      );

      expect(flags.isEnabled(newCheckout), isTrue);
      expect(errors, isNotEmpty);
    });

    test('a source that throws on refresh does not fail initialize', () async {
      final errors = <String?>[];
      final flags = FeatureFlags(
        registry: registry,
        sources: [_BrokenSource()],
        onError: (e, s, {sourceId, flagKey}) => errors.add(sourceId),
      );

      await flags.initialize();

      expect(errors, contains('broken'));
    });

    test('reading a flag missing from the registry is reported once', () {
      const ghost = BoolFlag(key: 'ghost', defaultValue: false);
      final errors = <Object>[];
      final flags = FeatureFlags(
        registry: registry,
        onError: (e, s, {sourceId, flagKey}) => errors.add(e),
      );

      flags.value(ghost);
      flags.value(ghost);

      expect(errors, hasLength(1));
      expect(errors.single, isStateError);
    });
  });

  test('changes stream emits when a source pushes', () async {
    final source = _MutableSource({});
    final flags = FeatureFlags(registry: registry, sources: [source]);

    final emitted = flags.changes.first;
    source.push('new_checkout', true);

    await emitted;
    expect(flags.isEnabled(newCheckout), isTrue);
  });

  test('resolveAll covers the whole registry, for the debug panel', () {
    final flags = FeatureFlags.defaults(registry);
    expect(flags.resolveAll().map((r) => r.flag.key),
        containsAll(['new_checkout', 'max_retries', 'theme']));
  });
}
