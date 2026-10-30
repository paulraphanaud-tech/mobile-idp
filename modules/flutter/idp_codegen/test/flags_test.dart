import 'package:idp_codegen/src/flags/codegen.dart';
import 'package:idp_codegen/src/flags/model.dart';
import 'package:idp_codegen/src/flags/parser.dart';
import 'package:idp_codegen/src/flags/render.dart';
import 'package:test/test.dart';

({FlagRegistryParser parser, FlagRegistry registry}) run(String yaml) {
  final parser = FlagRegistryParser();
  final registry = parser.parse(yaml, 'flags.yaml');
  return (parser: parser, registry: registry);
}

List<String> errorsIn(String yaml) =>
    run(yaml).parser.diagnostics.errors.map((d) => d.message).toList();

void main() {
  group('validation rejects', () {
    test('a key that is not snake_case', () {
      final errors = errorsIn('''
flags:
  - key: newCheckout
    type: bool
    default: false
''');
      expect(errors.join(), contains('snake_case'));
    });

    test('a missing default', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
''');
      expect(errors.join(), contains('missing "default"'));
    });

    test('a default whose type does not match the declaration', () {
      // The YAML mistake that matters: "false" is a string, and a string is
      // truthy in enough places that it survives to production.
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
    default: "false"
''');
      expect(errors.join(), contains('declared "bool"'));
    });

    test('a duplicate key', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
    default: false
  - key: a_flag
    type: bool
    default: true
''');
      expect(errors.join(), contains('duplicate'));
    });

    test('an unknown environment', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
    default: false
    environments:
      producton: true
''');
      expect(errors.join(), contains('unknown environment'));
    });

    test('an unknown rule condition, which would target everyone', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
    default: false
    environments:
      prod:
        value: false
        rules:
          - when:
              platfrom: [ios]
            value: true
''');
      expect(errors.join(), contains('unknown condition'));
    });

    test('a rollout percentage outside 0-100', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: bool
    default: false
    environments:
      prod:
        value: false
        rules:
          - rollout: {percentage: 150}
            value: true
''');
      expect(errors.join(), contains('outside 0–100'));
    });

    test('a default outside allowed_values', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: string
    default: sepia
    allowed_values: [light, dark]
''');
      expect(errors.join(), contains('allowed_values'));
    });

    test('a default outside min/max', () {
      final errors = errorsIn('''
flags:
  - key: a_flag
    type: int
    default: 0
    min: 5
''');
      expect(errors.join(), contains('below min'));
    });

    test('a key that generates a Dart keyword', () {
      final errors = errorsIn('''
flags:
  - key: switch
    type: bool
    default: false
''');
      expect(errors.join(), contains('Dart keyword'));
    });
  });

  group('validation warns about', () {
    test('a flag with no owner or expiry', () {
      final warnings =
          run('''
flags:
  - key: a_flag
    type: bool
    default: false
''').parser.diagnostics.warnings.map((d) => d.message).join();

      expect(warnings, contains('owner'));
      expect(warnings, contains('expires'));
    });

    test('a rule that applies to everyone', () {
      final warnings = run('''
flags:
  - key: a_flag
    type: bool
    default: false
    owner: team
    expires: 2030-01-01
    description: x
    environments:
      prod:
        value: false
        rules:
          - value: true
''').parser.diagnostics.warnings.map((d) => d.message).join();

      expect(warnings, contains('applies to everyone'));
    });
  });

  test('reports every bad flag in one run, not just the first', () {
    final errors = errorsIn('''
flags:
  - key: BadOne
    type: bool
    default: false
  - key: bad_two
    type: nonsense
    default: false
  - key: bad_three
    type: int
''');
    expect(errors.length, greaterThanOrEqualTo(3));
  });

  group('rendering', () {
    const registry = '''
flags:
  - key: a_flag
    type: bool
    default: false
    owner: team
    expires: 2030-01-01
    description: x
    environments:
      prod:
        value: false
        rules:
          - when: {platform: [ios]}
            rollout: {percentage: 25}
            value: true
''';

    test('aws emits a bare scalar when a flag has no targeting', () {
      final json = renderAwsDocument(run(registry).registry, 'dev');
      expect(json, contains('"a_flag": false'));
    });

    test('aws emits rules for the targeted environment', () {
      final json = renderAwsDocument(run(registry).registry, 'prod');
      expect(json, contains('"percentage": 25'));
      expect(json, contains('"platform"'));
    });

    test('firebase translates platform and percentage', () {
      final result = renderFirebaseTemplate(run(registry).registry, 'prod');
      expect(result.diagnostics.hasErrors, isFalse);
      expect(result.json, contains("device.os == 'ios'"));
      expect(result.json, contains("percent('a_flag') <= 25"));
      expect(result.json, contains('"valueType": "BOOLEAN"'));
    });

    test('firebase refuses conditions it cannot express faithfully', () {
      final result = renderFirebaseTemplate(
          run('''
flags:
  - key: a_flag
    type: bool
    default: false
    owner: team
    expires: 2030-01-01
    description: x
    environments:
      prod:
        value: false
        rules:
          - when: {user_id: [alice]}
            value: true
''').registry,
          'prod');

      expect(result.diagnostics.hasErrors, isTrue);
      expect(result.diagnostics.errors.first.message, contains('user_id'));
    });

    test('firebase stringifies every value, as Remote Config requires', () {
      final result = renderFirebaseTemplate(
          run('''
flags:
  - key: a_number
    type: int
    default: 30
    owner: team
    expires: 2030-01-01
    description: x
''').registry,
          'prod');

      expect(result.json, contains('"value": "30"'));
      expect(result.json, contains('"valueType": "NUMBER"'));
    });
  });

  test('generated Dart names the constant in lowerCamel', () {
    final dart = generateFlagsDart(run('''
flags:
  - key: new_checkout
    type: bool
    default: false
    owner: team
    expires: 2030-01-01
    description: x
''').registry);

    expect(dart, contains('static const newCheckout = BoolFlag('));
    expect(dart, contains("key: 'new_checkout'"));
    expect(dart, contains('static const List<Flag<Object>> all'));
  });
}
