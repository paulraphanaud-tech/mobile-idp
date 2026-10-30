import 'package:idp_feature_flags_aws/idp_feature_flags_aws.dart';
import 'package:test/test.dart';

EvaluationContext ctx(String id, {String? platform, String? version, String? userId, String? country, Map<String, Object?> attrs = const {}}) =>
    EvaluationContext(
      stableId: id,
      platform: platform,
      appVersion: version,
      userId: userId,
      country: country,
      attributes: attrs,
    );

void main() {
  group('bucketOf', () {
    test('is stable across calls', () {
      expect(bucketOf('f', 'device-1'), bucketOf('f', 'device-1'));
    });

    test('stays within range', () {
      for (var i = 0; i < 500; i++) {
        final b = bucketOf('flag', 'device-$i');
        expect(b, greaterThanOrEqualTo(0));
        expect(b, lessThan(100));
      }
    });

    test('distributes roughly evenly', () {
      const n = 20000;
      var under25 = 0;
      for (var i = 0; i < n; i++) {
        if (bucketOf('checkout', 'device-$i') < 25) under25++;
      }
      // Binomial noise at this n is well under a point; 2 points is generous
      // and keeps the test from flaking.
      expect(under25 / n * 100, closeTo(25, 2));
    });

    test('different seeds select different users', () {
      // The point of seeding per flag: two 25% rollouts must not pick the same
      // quarter of the population, or their results become correlated.
      const n = 5000;
      var both = 0;
      var eitherCount = 0;
      for (var i = 0; i < n; i++) {
        final a = bucketOf('flag_a', 'device-$i') < 25;
        final b = bucketOf('flag_b', 'device-$i') < 25;
        if (a && b) both++;
        if (a || b) eitherCount++;
      }
      expect(eitherCount, greaterThan(0));
      // Independent 25% rollouts overlap on ~6.25%, not ~25%.
      expect(both / n * 100, closeTo(6.25, 2));
    });
  });

  group('compareVersions', () {
    test('compares numerically, not lexically', () {
      expect(compareVersions('2.10.0', '2.9.0'), greaterThan(0));
    });

    test('treats missing segments as zero', () {
      expect(compareVersions('2.1', '2.1.0'), 0);
    });

    test('ignores pre-release and build suffixes', () {
      expect(compareVersions('2.1.0-beta.3', '2.1.0'), 0);
      expect(compareVersions('2.1.0+42', '2.1.0'), 0);
    });
  });

  group('RuleConditions', () {
    test('an empty condition set matches everyone', () {
      expect(const RuleConditions().matches(ctx('d')), isTrue);
    });

    test('platform match is case-insensitive', () {
      const c = RuleConditions(platforms: ['iOS']);
      expect(c.matches(ctx('d', platform: 'ios')), isTrue);
      expect(c.matches(ctx('d', platform: 'android')), isFalse);
    });

    test('conditions are ANDed', () {
      const c = RuleConditions(platforms: ['ios'], countries: ['FR']);
      expect(c.matches(ctx('d', platform: 'ios', country: 'FR')), isTrue);
      expect(c.matches(ctx('d', platform: 'ios', country: 'DE')), isFalse);
    });

    test('min_app_version compares numerically', () {
      const c = RuleConditions(minAppVersion: '2.9.0');
      expect(c.matches(ctx('d', version: '2.10.0')), isTrue);
      expect(c.matches(ctx('d', version: '2.8.9')), isFalse);
    });

    test('a version rule fails closed when the version is unknown', () {
      const c = RuleConditions(minAppVersion: '2.0.0');
      expect(c.matches(ctx('d')), isFalse,
          reason: 'must not reach clients of unknown version');
    });

    test('user allowlist', () {
      const c = RuleConditions(userIds: ['alice', 'bob']);
      expect(c.matches(ctx('d', userId: 'alice')), isTrue);
      expect(c.matches(ctx('d', userId: 'carol')), isFalse);
    });

    test('custom attributes', () {
      final c = RuleConditions.fromJson({
        'attributes': {'plan': ['pro', 'enterprise']}
      });
      expect(c.matches(ctx('d', attrs: {'plan': 'pro'})), isTrue);
      expect(c.matches(ctx('d', attrs: {'plan': 'free'})), isFalse);
    });
  });

  group('TargetingRule', () {
    test('returns null when conditions do not match', () {
      const rule = TargetingRule(
        value: true,
        conditions: RuleConditions(platforms: ['ios']),
      );
      expect(rule.evaluate('f', ctx('d', platform: 'android')), isNull);
    });

    test('100 percent means everyone who matches', () {
      const rule = TargetingRule(value: true, percentage: 100);
      for (var i = 0; i < 100; i++) {
        expect(rule.evaluate('f', ctx('device-$i')), isTrue);
      }
    });

    test('0 percent means nobody', () {
      const rule = TargetingRule(value: true, percentage: 0);
      for (var i = 0; i < 100; i++) {
        expect(rule.evaluate('f', ctx('device-$i')), isNull);
      }
    });

    test('a device inside the rollout stays inside it', () {
      const rule = TargetingRule(value: true, percentage: 50);
      final first = rule.evaluate('f', ctx('device-7'));
      for (var i = 0; i < 20; i++) {
        expect(rule.evaluate('f', ctx('device-7')), first);
      }
    });
  });
}
