# idp_feature_flags_aws

AWS-backed `FlagSource` for [`idp_feature_flags`](../idp_feature_flags): a flag
document published to S3, served through CloudFront, with targeting evaluated
on device.

```dart
AwsFlagSource(
  url: Uri.parse(const String.fromEnvironment('FLAGS_URL')),
  context: EvaluationContext(
    stableId: installId,        // persisted, NOT a per-session uuid
    platform: Platform.isIOS ? 'ios' : 'android',
    appVersion: packageInfo.version,
  ),
  loadCache: () async => prefs.getString('flags_doc'),
  saveCache: (body) => prefs.setString('flags_doc', body),
);
```

## Why not the AppConfig Data API

AWS AppConfig is the obvious-sounding answer and it is the wrong one for a
mobile client:

- its API is **SigV4-signed**, so reaching it from a phone means shipping a
  Cognito identity pool that mints AWS credentials for anyone who asks
- it **bills per configuration request**, with no CDN in front
- it is built for a fleet of servers, not millions of devices

A published JSON document behind CloudFront has none of those problems: no AWS
credentials in the binary, edge-cached, effectively free at any install base.
The one thing AppConfig would have contributed — staged rollout — is covered by
client-side targeting, which is strictly more useful here because it addresses
*users* rather than config propagation.

## Document format

`make flags-publish` generates this from `flags/flags.yaml`; you should not
write it by hand.

```json
{
  "schema": 1,
  "environment": "dev",
  "published_at": "2026-09-16T10:00:00Z",
  "flags": {
    "dark_mode": true,
    "new_checkout": {
      "value": false,
      "rules": [
        { "when": { "user_id": ["alice", "bob"] }, "value": true },
        { "when": { "platform": ["ios"], "min_app_version": "2.1.0" },
          "rollout": { "percentage": 25 },
          "value": true }
      ]
    }
  }
}
```

A bare scalar is shorthand for "this value, no targeting" — which most flags
are, and spelling them all out as objects makes the document tedious to review.

Rules are evaluated **in order, first match wins**. Within a rule every `when`
condition must hold (AND); an absent `when` matches everyone. Supported
conditions: `platform`, `country`, `locale`, `user_id`, `min_app_version`,
`max_app_version`, and `attributes` for anything custom.

A rule whose conditions match but whose rollout percentage excludes this device
falls through to the **next rule**, not to the default.

## Percentage rollouts

Bucketing is FNV-1a over `"<seed>:<stableId>"`, giving three properties:

- **Stable** — the same device always lands in the same bucket, so a user does
  not flip in and out of an experiment between launches. This is why
  `stableId` must be a persisted install id.
- **Per-flag** — the seed defaults to the flag key, so two independent 25%
  rollouts do not select the *same* quarter of users. Sharing a bucket across
  flags silently correlates experiments and makes their results
  uninterpretable. Set an explicit `seed` only when you want mutually exclusive
  or deliberately aligned cohorts.
- **Client-side** — no round trip, so rollouts work offline and on the first
  frame.

Granularity is 0.01%, so a 0.5% canary is expressible.

## Failure behaviour

Every one of these keeps the **previous** document and reports nothing:

| Situation | Why it is not an error |
|---|---|
| Offline / timeout | The normal case on mobile. |
| `304 Not Modified` | The expected case — this is what makes a short refresh interval cheap. |
| `403` | What CloudFront returns for a missing object with origin access control. Means nobody has published this environment yet. |
| Malformed body | The ETag is deliberately **not** recorded, so the next refresh retries instead of being told "not modified" about an unusable body. |
| `schema` newer than the client | Old app versions stay on last-known-good rather than misreading a format they do not understand. |

`initialize` loads `loadCache` **before** any network call, so the first frame
after a cold start sees last-known-good values rather than bundled defaults.
