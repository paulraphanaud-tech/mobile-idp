import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:idp_feature_flags/idp_feature_flags.dart';

import 'evaluation_context.dart';
import 'flag_document.dart';

/// Reads flags from a document published to S3 and served through CloudFront.
///
/// ## Why a static document rather than the AppConfig Data API
///
/// AWS AppConfig is the obvious-sounding answer, and it is the wrong one for a
/// mobile client. Its API is SigV4-signed, so reaching it from a phone means
/// shipping a Cognito identity pool to mint credentials for anyone who asks,
/// it bills per configuration request with no CDN in front, and it is designed
/// for a fleet of servers rather than millions of devices.
///
/// A published JSON document behind CloudFront has none of those problems:
/// **no AWS credentials in the binary**, edge-cached, and effectively free at
/// any install base. What AppConfig would have given — staged rollout — is
/// provided instead by client-side targeting, which is strictly more useful
/// here because it can address *users* rather than config propagation.
///
/// ## Behaviour
///
/// * `initialize` loads the last-known-good document from [loadCache] before
///   any network call, so the first frame after a cold start sees real flag
///   values rather than bundled defaults.
/// * `refresh` revalidates with `If-None-Match`; a 304 costs almost nothing,
///   which is what makes a short [ttl] affordable.
/// * Every network failure keeps the previous document. Offline is the normal
///   case for a mobile app, not an error worth reporting.
class AwsFlagSource extends FlagSourceBase {
  AwsFlagSource({
    required this.url,
    required EvaluationContext context,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
    this.loadCache,
    this.saveCache,
  })  : _context = context,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Full URL of the published document, e.g.
  /// `https://d111111abcdef8.cloudfront.net/dev/flags.json`.
  /// `make infra-output` reports it as `flags_document_url`.
  final Uri url;

  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  /// Returns the cached document body, or null. Back it with whatever storage
  /// the app already has — this package does not pull one in.
  final Future<String?> Function()? loadCache;

  /// Persists a freshly fetched document body.
  final Future<void> Function(String body)? saveCache;

  final _changes = StreamController<void>.broadcast();

  EvaluationContext _context;
  FlagDocument? _document;
  String? _etag;

  @override
  String get id => 'aws';

  @override
  Stream<void> get changes => _changes.stream;

  /// The document currently in effect. Null before the first successful fetch
  /// or cache load. Useful in a debug panel: `publishedAt` answers "how stale
  /// are my flags?".
  FlagDocument? get document => _document;

  EvaluationContext get context => _context;

  /// Replaces the targeting context — after login, say, when [userId] becomes
  /// known and user-allowlist rules can start matching.
  ///
  /// Keep [EvaluationContext.stableId] unchanged unless you intend to re-bucket
  /// every rollout for this device.
  void updateContext(EvaluationContext context) {
    _context = context;
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> initialize(List<Flag<Object>> registry) async {
    final cached = await loadCache?.call();
    if (cached == null) return;
    try {
      _document = FlagDocument.parse(cached);
    } catch (_) {
      // A corrupt cache is not worth reporting; the next refresh replaces it.
    }
  }

  @override
  Future<void> refresh() async {
    try {
      final response = await _client.get(url, headers: {
        if (_etag != null) 'If-None-Match': _etag!,
        'Accept': 'application/json',
      }).timeout(timeout);

      // Not modified — by far the most common outcome, and the reason a short
      // refresh interval is cheap.
      if (response.statusCode == 304) return;

      if (response.statusCode != 200) {
        // 403 from CloudFront is what a missing object looks like with origin
        // access control in place; it means nobody has published this
        // environment yet. Either way the previous document stands.
        return;
      }

      final body = response.body;
      final parsed = FlagDocument.parse(body);

      _document = parsed;
      _etag = response.headers['etag'];
      await saveCache?.call(body);

      if (!_changes.isClosed) _changes.add(null);
    } on FormatException catch (_) {
      // A malformed or too-new document. Keep the previous one; do not cache
      // the bad body, and do not record its ETag, so the next refresh retries
      // rather than being told "not modified" about something unusable.
    } on TimeoutException catch (_) {
      // Ordinary on a mobile network.
    } catch (_) {
      // SocketException and friends. Offline is the normal case.
    }
  }

  @override
  Object? read(String key) => _document?.evaluate(key, _context);

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
    await _changes.close();
  }
}
