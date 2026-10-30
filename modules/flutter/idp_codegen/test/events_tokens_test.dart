import 'package:idp_codegen/src/events/codegen.dart';
import 'package:idp_codegen/src/events/model.dart';
import 'package:idp_codegen/src/events/parser.dart';
import 'package:idp_codegen/src/tokens/codegen.dart';
import 'package:idp_codegen/src/tokens/model.dart';
import 'package:idp_codegen/src/tokens/parser.dart';
import 'package:test/test.dart';

({EventRegistryParser parser, EventRegistry registry}) events(String yaml) {
  final parser = EventRegistryParser();
  return (parser: parser, registry: parser.parse(yaml, 'events.yaml'));
}

String eventErrors(String yaml) =>
    events(yaml).parser.diagnostics.errors.map((d) => d.message).join(' | ');

({TokenParser parser, TokenSet tokens}) tokens(String json) {
  final parser = TokenParser();
  return (parser: parser, tokens: parser.parse(json, 'tokens.json'));
}

String tokenErrors(String json) =>
    tokens(json).parser.diagnostics.errors.map((d) => d.message).join(' | ');

const _minimalColors = '''
    "primary": "#4F46E5", "on_primary": "#FFFFFF",
    "secondary": "#0D9488", "on_secondary": "#FFFFFF",
    "surface": "#FFFFFF", "on_surface": "#111827",
    "error": "#DC2626", "on_error": "#FFFFFF"
''';

void main() {
  group('event registry rejects', () {
    test('a reserved GA4 prefix, which is silently never recorded', () {
      expect(eventErrors('''
events:
  - name: firebase_thing
'''), contains('reserved'));
    });

    test('an event GA4 already collects itself', () {
      expect(eventErrors('''
events:
  - name: session_start
'''), contains('collected automatically'));
    });

    test('an event name over 40 characters', () {
      final long = 'a_${'x' * 45}';
      expect(eventErrors('events:\n  - name: $long\n'), contains('40'));
    });

    test('more than 25 parameters', () {
      final params = List.generate(
          26, (i) => '      - name: p_$i\n        type: string').join('\n');
      expect(
        eventErrors('events:\n  - name: big_event\n    parameters:\n$params\n'),
        contains('25'),
      );
    });

    test('a duplicate parameter', () {
      expect(eventErrors('''
events:
  - name: an_event
    parameters:
      - name: dupe
        type: string
      - name: dupe
        type: int
'''), contains('duplicate parameter'));
    });

    test('an unknown parameter type', () {
      expect(eventErrors('''
events:
  - name: an_event
    parameters:
      - name: p
        type: datetime
'''), contains('unknown "type"'));
    });
  });

  test('generated event omits optional parameters rather than sending null', () {
    final dart = generateEventsDart(events('''
events:
  - name: checkout_started
    description: x
    owner: team
    parameters:
      - name: cart_value
        type: double
        required: true
      - name: coupon_code
        type: string
''').registry);

    expect(dart, contains('class CheckoutStarted extends AnalyticsEvent'));
    expect(dart, contains('required this.cartValue'));
    expect(dart, contains('final double cartValue;'));
    expect(dart, contains('final String? couponCode;'));
    expect(dart, contains("if (couponCode != null) 'coupon_code': couponCode,"));
  });

  group('token file rejects', () {
    test('a missing ColorScheme role', () {
      expect(tokenErrors('{"color": {"primary": "#FFFFFF"}}'),
          contains('missing required colour role'));
    });

    test('a colour without a leading hash', () {
      expect(tokenErrors('{"color": {"primary": "4F46E5"}}'),
          contains('must start with "#"'));
    });

    test('a malformed hex colour', () {
      expect(tokenErrors('{"color": {"primary": "#GGGGGG"}}'),
          contains('not a valid hex'));
    });

    test('a negative spacing step', () {
      expect(
        tokenErrors('{"color": {$_minimalColors}, "spacing": {"xs": -4}}'),
        contains('negative'),
      );
    });

    test('a font weight that is not a multiple of 100', () {
      expect(
        tokenErrors(
            '{"color": {$_minimalColors}, "typography": {"body": {"size": 16, "weight": 450}}}'),
        contains('multiple of 100'),
      );
    });
  });

  test('token file warns when line height looks like pixels', () {
    final warnings = tokens(
            '{"color": {$_minimalColors}, "typography": {"body_large": {"size": 16, "height": 24}}}')
        .parser
        .diagnostics
        .warnings
        .map((d) => d.message)
        .join();

    expect(warnings, contains('multiple of font size'));
  });

  test('hex shorthand and alpha are both accepted', () {
    final set = tokens('{"color": {$_minimalColors, "a": "#F00", "b": "#80FF0000"}}').tokens;
    expect(set.color('a')!.light, 0xFFFF0000);
    expect(set.color('b')!.light, 0x80FF0000);
  });

  test('a bare colour string means the same value in both modes', () {
    final token = tokens('{"color": {$_minimalColors, "brand": "#F43F5E"}}')
        .tokens
        .color('brand')!;
    expect(token.isModeIndependent, isTrue);
  });

  test('generated theme pins named roles onto a derived scheme', () {
    final dart = generateTokensDart(
        tokens('{"color": {$_minimalColors}, "spacing": {"md": 16}}').tokens);

    expect(dart, contains('class AppColors extends ThemeExtension<AppColors>'));
    expect(dart, contains('ColorScheme.fromSeed('));
    expect(dart, contains('primary: colors.primary,'));
    expect(dart, contains('AppSpacing get spacing'));
  });
}
