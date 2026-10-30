// Composition root for the platform services the IDP provides: analytics,
// feature flags and the generated theme.
//
// This file is YOURS — the bootstrap copies it once and never touches it
// again. Edit it freely; it is a worked starting point, not generated code.
//
// Everything it wires up is deliberately injected rather than reached for
// globally, so a widget test can substitute a MemoryAnalyticsSink and a
// StaticFlagSource without any of this running.

import 'package:idp_analytics/idp_analytics.dart';
import 'package:idp_feature_flags/idp_feature_flags.dart';

// Uncomment the backends this project actually uses, and add them to pubspec.
// import 'package:idp_analytics_firebase/idp_analytics_firebase.dart';
// import 'package:idp_feature_flags_firebase/idp_feature_flags_firebase.dart';
// import 'package:idp_feature_flags_aws/idp_feature_flags_aws.dart';

import 'generated/events.g.dart';
import 'generated/flags.g.dart';

/// Compiled in by `--dart-define`, which fastlane sets from `FLAGS_URL` in
/// `fastlane/env.<env>` (or, in CI, from Terraform). Empty means no remote
/// backend, and the app runs on the defaults in `flags/flags.yaml`.
const flagsUrl = String.fromEnvironment('FLAGS_URL');

/// Which backend this binary was built against. Surface both of these in a
/// debug screen: "flags look wrong" is usually "this build points at the wrong
/// environment", and that is otherwise invisible from inside the app.
const flagsBackend = String.fromEnvironment('FLAGS_BACKEND', defaultValue: 'none');

/// The platform services, assembled.
class Idp {
  Idp._({required this.analytics, required this.flags});

  final Analytics analytics;
  final FeatureFlags flags;

  /// Builds and starts everything.
  ///
  /// Call after `Firebase.initializeApp()` if a Firebase backend is in use, and
  /// before `runApp`. It does not block on the network: flag sources serve
  /// their bundled defaults until the first fetch lands, so a slow or absent
  /// connection delays nothing.
  static Future<Idp> initialize({
    required String stableId,
    required String appVersion,
    required String platform,
    bool debug = false,
    Consent consent = Consent.unknown,
    void Function(Object error, StackTrace stack, String context)? onError,
  }) async {
    void report(Object error, StackTrace stack, String context) {
      // Wire this to Crashlytics or Sentry. Left as a callback because a
      // platform that hard-codes its own error reporter is a platform every
      // project has to fork.
      onError?.call(error, stack, context);
    }

    final analytics = Analytics(
      sinks: [
        if (debug) ConsoleAnalyticsSink(),
        // FirebaseAnalyticsSink(),
        //
        // A second vendor goes here, next to the first — not at call sites:
        // AmplitudeSink(apiKey: ...),
      ],
      consent: consent,
      onError: (e, s, {sinkId, operation}) =>
          report(e, s, 'analytics/${sinkId ?? '?'}/${operation ?? '?'}'),
    );

    // Overrides let a developer or tester force a flag on one device without
    // touching the backend. Disabled outside debug builds so one left behind
    // cannot ship.
    final overrides = FlagOverrideStore(enabled: debug);

    final flags = FeatureFlags(
      registry: Flags.all,
      overrides: overrides,
      sources: [
        // Pick one. Both read the same flags/flags.yaml.
        //
        // if (flagsUrl.isNotEmpty)
        //   AwsFlagSource(
        //     url: Uri.parse(flagsUrl),
        //     context: EvaluationContext(
        //       stableId: stableId,     // persisted install id, NOT per-session
        //       platform: platform,
        //       appVersion: appVersion,
        //     ),
        //     // Back these with SharedPreferences so the first frame after a
        //     // cold start sees last-known-good values, not bundled defaults.
        //     loadCache: () async => prefs.getString('flags_doc'),
        //     saveCache: (body) => prefs.setString('flags_doc', body),
        //   ),
        //
        // RemoteConfigFlagSource(),
      ],

      // Exposure: which users actually saw which variant. This is what makes an
      // experiment measurable — without it you know who was bucketed, which
      // includes everyone who never reached the screen.
      onExposure: (r) => analytics.log(FlagExposed(
        flagKey: r.flag.key,
        flagValue: '${r.value}',
        flagSource: r.sourceId ?? 'default',
      )),

      onError: (e, s, {sourceId, flagKey}) =>
          report(e, s, 'flags/${sourceId ?? '?'}/${flagKey ?? '?'}'),
    );

    await flags.initialize();

    return Idp._(analytics: analytics, flags: flags);
  }

  /// Call on resume and after login — the first picks up a rollout that started
  /// while the app was backgrounded, the second lets user-targeted rules match.
  Future<void> refresh() => flags.refresh();

  Future<void> dispose() async {
    await analytics.dispose();
    await flags.dispose();
  }
}
