import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idp_feature_flags/idp_feature_flags.dart';
import 'package:idp_feature_flags_aws/idp_feature_flags_aws.dart';
import 'package:test/test.dart';

final url = Uri.parse('https://cdn.example.test/dev/flags.json');

const device = EvaluationContext(
  stableId: 'device-1',
  platform: 'ios',
  appVersion: '2.1.0',
);

String doc(Map<String, Object?> flags, {int schema = 1}) => jsonEncode({
      'schema': schema,
      'environment': 'dev',
      'published_at': '2026-09-16T10:00:00Z',
      'flags': flags,
    });

void main() {
  group('FlagDocument', () {
    test('accepts a bare scalar as shorthand for an untargeted value', () {
      final d = FlagDocument.parse(doc({'new_checkout': true}));
      expect(d.evaluate('new_checkout', device), isTrue);
    });

    test('reads metadata', () {
      final d = FlagDocument.parse(doc({}));
      expect(d.environment, 'dev');
      expect(d.publishedAt, DateTime.utc(2026, 9, 16, 10));
    });

    test('returns null for a flag it does not mention', () {
      expect(FlagDocument.parse(doc({})).evaluate('absent', device), isNull);
    });

    test('first matching rule wins', () {
      final d = FlagDocument.parse(doc({
        'theme': {
          'value': 'light',
          'rules': [
            {'when': {'platform': ['android']}, 'value': 'android-theme'},
            {'when': {'platform': ['ios']}, 'value': 'ios-theme'},
          ],
        },
      }));
      expect(d.evaluate('theme', device), 'ios-theme');
    });

    test('falls back to the environment value when no rule applies', () {
      final d = FlagDocument.parse(doc({
        'theme': {
          'value': 'light',
          'rules': [
            {'when': {'platform': ['android']}, 'value': 'dark'},
          ],
        },
      }));
      expect(d.evaluate('theme', device), 'light');
    });

    test('rejects a schema newer than this client understands', () {
      expect(
        () => FlagDocument.parse(doc({}, schema: 99)),
        throwsFormatException,
      );
    });

    test('rejects non-JSON and shapes it cannot read', () {
      expect(() => FlagDocument.parse('not json'), throwsFormatException);
      expect(() => FlagDocument.parse('[]'), throwsFormatException);
      expect(() => FlagDocument.parse('{"schema":1}'), throwsFormatException);
    });
  });

  group('AwsFlagSource', () {
    test('fetches and serves values', () async {
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((_) async => http.Response(
              doc({'new_checkout': true}),
              200,
              headers: {'etag': '"v1"'},
            )),
      );

      await source.refresh();

      expect(source.read('new_checkout'), isTrue);
      await source.close();
    });

    test('revalidates with If-None-Match and keeps values on 304', () async {
      var calls = 0;
      String? sentEtag;
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((request) async {
          calls++;
          sentEtag = request.headers['If-None-Match'];
          if (calls == 1) {
            return http.Response(doc({'new_checkout': true}), 200,
                headers: {'etag': '"v1"'});
          }
          return http.Response('', 304);
        }),
      );

      await source.refresh();
      await source.refresh();

      expect(sentEtag, '"v1"');
      expect(source.read('new_checkout'), isTrue, reason: '304 keeps values');
      await source.close();
    });

    test('keeps the previous document when the network fails', () async {
      var calls = 0;
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response(doc({'new_checkout': true}), 200);
          }
          throw const SocketException('offline');
        }),
      );

      await source.refresh();
      await source.refresh();

      expect(source.read('new_checkout'), isTrue);
      await source.close();
    });

    test('keeps the previous document when the body is malformed', () async {
      var calls = 0;
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response(doc({'new_checkout': true}), 200,
                headers: {'etag': '"v1"'});
          }
          return http.Response('{{{ truncated', 200, headers: {'etag': '"v2"'});
        }),
      );

      await source.refresh();
      await source.refresh();

      expect(source.read('new_checkout'), isTrue);
      expect(source.document?.flags, contains('new_checkout'));
      await source.close();
    });

    test('does not record the ETag of a body it rejected', () async {
      final sent = <String?>[];
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((request) async {
          sent.add(request.headers['If-None-Match']);
          return http.Response('garbage', 200, headers: {'etag': '"bad"'});
        }),
      );

      await source.refresh();
      await source.refresh();

      expect(sent, [null, null],
          reason: 'otherwise the server answers 304 about an unusable body');
      await source.close();
    });

    test('a 403 (nothing published yet) is not fatal', () async {
      final source = AwsFlagSource(
        url: url,
        context: device,
        client: MockClient((_) async => http.Response('', 403)),
      );

      await source.refresh();

      expect(source.read('anything'), isNull);
      await source.close();
    });

    test('serves the cached document before any network call', () async {
      final source = AwsFlagSource(
        url: url,
        context: device,
        loadCache: () async => doc({'new_checkout': true}),
        client: MockClient((_) async => http.Response('', 500)),
      );

      await source.initialize(const []);

      expect(source.read('new_checkout'), isTrue,
          reason: 'first frame after cold start should not be bundled defaults');
      await source.close();
    });

    test('persists a freshly fetched document', () async {
      String? saved;
      final source = AwsFlagSource(
        url: url,
        context: device,
        saveCache: (body) async => saved = body,
        client: MockClient(
            (_) async => http.Response(doc({'new_checkout': true}), 200)),
      );

      await source.refresh();

      expect(saved, isNotNull);
      expect(FlagDocument.parse(saved!).evaluate('new_checkout', device), isTrue);
      await source.close();
    });

    test('a corrupt cache is ignored rather than fatal', () async {
      final source = AwsFlagSource(
        url: url,
        context: device,
        loadCache: () async => 'corrupt',
        client: MockClient((_) async => http.Response('', 500)),
      );

      await source.initialize(const []);

      expect(source.document, isNull);
      await source.close();
    });

    test('updating the context re-evaluates targeting', () async {
      final source = AwsFlagSource(
        url: url,
        context: const EvaluationContext(stableId: 'd', platform: 'android'),
        client: MockClient((_) async => http.Response(
              doc({
                'beta': {
                  'value': false,
                  'rules': [
                    {'when': {'user_id': ['alice']}, 'value': true},
                  ],
                },
              }),
              200,
            )),
      );

      await source.refresh();
      expect(source.read('beta'), isFalse);

      source.updateContext(source.context.copyWith(userId: 'alice'));
      expect(source.read('beta'), isTrue, reason: 'allowlist applies at login');
      await source.close();
    });
  });

  test('integrates with FeatureFlags end to end', () async {
    const newCheckout = BoolFlag(key: 'new_checkout', defaultValue: false);
    final source = AwsFlagSource(
      url: url,
      context: device,
      client: MockClient((_) async => http.Response(
            doc({
              'new_checkout': {
                'value': false,
                'rules': [
                  {
                    'when': {'platform': ['ios'], 'min_app_version': '2.0.0'},
                    'rollout': {'percentage': 100},
                    'value': true,
                  },
                ],
              },
            }),
            200,
          )),
    );

    final flags = FeatureFlags(registry: [newCheckout], sources: [source]);
    expect(flags.isEnabled(newCheckout), isFalse, reason: 'bundled default');

    await flags.initialize();

    expect(flags.isEnabled(newCheckout), isTrue);
    expect(flags.resolve(newCheckout).sourceId, 'aws');
    await flags.dispose();
  });
}
