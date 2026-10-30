# Feature flags

`flags/flags.yaml` is the source of truth. Everything else — the typed Dart
constants, the published document, what the backend serves — is derived from
it.

```
flags/flags.yaml
   │
   ├── make codegen       ──► lib/generated/flags.g.dart   (typed constants)
   │
   └── make flags-publish ──► the backend                  (values + targeting)
```

Editing flags in a backend console works until the next publish overwrites it.
That is deliberate: flag state should be reviewable, attributable and
revertable like any other change.

## Declaring a flag

```yaml
flags:
  - key: new_checkout          # snake_case; used verbatim as the backend key
    type: bool                 # bool | string | int | double | json
    default: false             # compiled into the binary — see below
    description: Routes checkout through the rebuilt flow.
    owner: payments            # who removes this flag
    expires: 2026-12-31        # when it should be gone
    environments:
      dev: true
      staging: true
      prod: false
```

### The default is not a placeholder

`default` is compiled into the app. Users get it:

- before the first fetch completes — **including the whole of the first frame**
- whenever the device is offline
- whenever a published value fails to decode

So it must be the safe choice. For a kill switch that means "feature on, kill
switch not pulled" — a kill switch defaulting to "killed" disables the feature
for every user on a flaky network.

### Constraints are enforced, not documented

```yaml
  - key: checkout_timeout_seconds
    type: int
    default: 30
    min: 5
    max: 120

  - key: promo_banner_variant
    type: string
    default: none
    allowed_values: [none, summer, winter]
```

A published value outside these is rejected on device and the default is used
instead. A typo in a console cannot put the app into a state the code has no
branch for.

## Targeting and rollouts

```yaml
    environments:
      prod:
        value: false
        rules:
          - when:
              user_id: [alice@example.com, bob@example.com]
            value: true
          - when:
              platform: [ios]
              min_app_version: "2.1.0"
            rollout:
              percentage: 25
            value: true
```

Rules are evaluated **in order, first match wins**. Within a rule every `when`
condition must hold; an absent `when` matches everyone. A rule whose conditions
match but whose rollout excludes this device falls through to the **next rule**,
not to the environment value.

Conditions: `platform`, `country`, `locale`, `user_id`, `min_app_version`,
`max_app_version`, `attributes`. A misspelled one is a validation **error**, not
a silent ignore — an ignored condition would make the rule target everybody.

Version rules **fail closed**: a client whose version is unknown does not match
`min_app_version`.

### Bucketing

Percentage rollouts hash `"<seed>:<stableId>"` with FNV-1a. The seed defaults
to the flag key, which matters more than it looks: two independent 25% rollouts
sharing a bucket would select the *same* quarter of users, silently correlating
two experiments and making both uninterpretable. Set an explicit `seed` only
when you want mutually exclusive or deliberately aligned cohorts.

`stableId` must be a **persisted install id**. A per-session UUID re-buckets
the user on every launch, so they flip in and out of the experiment and the
results are noise.

Granularity is 0.01%, so a 0.5% canary is expressible.

## Backends

Set `feature_flags_backend` in `infra/environments/<env>/terraform.tfvars`.
Both backends read the same `flags.yaml`; switching is a re-publish plus
changing which `FlagSource` the app constructs.

| | `aws` | `firebase` |
|---|---|---|
| Infrastructure | S3 bucket + CloudFront, created by `modules/terraform/feature_flags` | None — Remote Config lives on the Firebase project |
| App credentials | None. Plain cacheable HTTPS GET | Firebase SDK |
| Targeting | All conditions, evaluated on device | `platform`, `country`, percentage only |
| Per environment | Yes — `<env>/flags.json` | **No.** Remote Config is per Firebase *project* |
| Cost | CloudFront bytes. Negligible | Free |
| Propagation | CDN TTL (default 60s), invalidated on publish | Fetch interval, or realtime updates |

### Why not AWS AppConfig

AppConfig is the service literally called "feature flags", and it is the wrong
tool for a mobile client. Its data API is SigV4-signed, so reaching it from a
phone means shipping a Cognito identity pool that mints AWS credentials for
anyone who asks; it bills per configuration request with no CDN in front; and
it is built for a fleet of servers, not millions of devices.

A published document behind CloudFront has none of those problems. The staged
rollout AppConfig would have contributed is provided instead by client-side
targeting, which is strictly more useful here because it addresses *users*
rather than config propagation.

### The Firebase caveat, stated plainly

Remote Config has one template per Firebase project. This platform points all
three environments at one `gcp_project_id` by default, so **dev, staging and
prod would share one set of flag values**. Publishing `prod` overwrites what
`dev` published. Use separate Firebase projects per environment, or use the
`aws` backend.

The renderer also **refuses** to translate `user_id` and `attributes`
conditions to Remote Config rather than translating them wrongly — Remote
Config has no equivalent that targets the same people without routing through
Analytics user properties, which is a different mechanism with its own
propagation delay.

## Publishing

```bash
make flags-plan    ENV=dev     # read-only; diffs against what is live
make flags-publish ENV=dev
```

`flags-publish` runs the same diff first and does nothing if there is no
change. `ENV=prod` requires typing `publish flags prod`, because a flag change
reaches installed apps within the CDN TTL with no build and no app store review
in between. It is recoverable — the bucket is versioned, Remote Config keeps
template history — but users see it first.

Rolling back:

```bash
# aws: restore the previous object version
aws s3api list-object-versions --bucket <project>-flags --prefix prod/flags.json
aws s3api copy-object --bucket <project>-flags --key prod/flags.json \
  --copy-source '<project>-flags/prod/flags.json?versionId=<previous>'

# firebase
firebase remoteconfig:rollback --version-number <n>
```

Then fix `flags.yaml` and republish, or the next publish reinstates the bad
value.

## Reading a flag

```dart
if (flags.isEnabled(Flags.newCheckout)) { ... }
```

Synchronous and never throws. Before the first fetch it returns the bundled
default — design for that rather than blocking app start on a fetch.

To find out *why* a flag has its value:

```dart
final r = flags.resolve(Flags.newCheckout);
r.sourceId;      // 'aws' | 'remote_config' | 'override' | null (bundled default)
r.isOverridden;  // this device is not seeing what the backend would give it
```

## Exposure, and why it matters

```dart
onExposure: (r) => analytics.log(FlagExposed(
  flagKey: r.flag.key, flagValue: '${r.value}', flagSource: r.sourceId ?? 'default',
)),
```

This fires the first time each flag is actually **read** with a given value —
not when the user was bucketed. The difference decides whether an experiment
means anything: bucketing includes every user who never reached the screen, and
averaging over them dilutes the effect toward zero.

Fires once per flag-and-value per session, so it is safe despite flags being
read in `build()`. It refires after a mid-session change.

## Flag debt

Every flag is temporary. `make flags-audit` lists the ones past `expires` and
the ones with no date at all:

```
3 flags in flags/flags.yaml
  1 past their expiry date
  0 with no expiry date

Past due — these should have been removed:
  new_checkout    expired 2026-12-31  owner: payments
```

It is read-only and never fails a build: flag debt is a standing conversation,
not a reason to block tonight's release. To make it blocking in a periodic job,
use `idp_codegen flags validate --strict-expiry`.

Removing a flag means deleting the entry, regenerating, **and deleting the
branch it guarded**. A flag removed from the registry but left in the code
resolves to its default forever, which is the quiet way a rollout gets stuck at
100% of nothing.

## Local overrides

```dart
FlagOverrideStore(enabled: kDebugMode)
```

Beats every remote source, so a tester can force a flag on one device without
touching the backend. `enabled: false` makes it have no opinion at all, so an
override left behind cannot ship.
