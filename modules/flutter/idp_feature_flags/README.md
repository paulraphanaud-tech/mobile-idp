# idp_feature_flags

Vendor-neutral feature flags. The app depends on **this package only**;
backends arrive as separate packages implementing `FlagSource`.

## Resolution order

First match wins:

1. `FlagOverrideStore` — a developer or QA forcing a value on this device
2. each `FlagSource` in order — normally the remote backend
3. the flag's `defaultValue`, compiled into the binary

```dart
final flags = FeatureFlags(
  registry: Flags.all,                    // generated from flags/flags.yaml
  overrides: FlagOverrideStore(enabled: kDebugMode),
  sources: [RemoteConfigFlagSource()],    // or AppConfigFlagSource()
  onExposure: (r) => analytics.log(FlagExposed(r.flag.key, '${r.value}')),
  onError: (e, s, {sourceId, flagKey}) =>
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'flags/$sourceId'),
);
await flags.initialize();
```

## Reads are synchronous

```dart
if (flags.isEnabled(Flags.newCheckout)) { ... }
```

Deliberately not `Future<bool>`. Flags are read inside `build()`, and an async
read there turns every flagged widget into a `FutureBuilder` with a loading
state. Sources keep an in-memory snapshot updated by `refresh()`; `read()` only
looks at that snapshot.

The consequence to design for: **before the first fetch completes, every flag
is its bundled default.** So the default must be the safe choice — for a kill
switch, that means "feature on, kill switch not pulled". Don't block app start
on a fetch to avoid this; hold the splash only for the handful of flags that
change the first frame.

## Reads never throw

Offline, throttled, or a backend returning `"maybe"` for a boolean all produce
the bundled default. Undecodable values are reported once through `onError` —
not once per rebuild — and `FlagResolution.decodeFailed` marks them.

`min`/`max` on numeric flags and `allowedValues` on string flags are enforced
at resolution. A typo in a backend console cannot put the app into a state the
code has no branch for.

## Attribution

`resolve()` returns where the value came from, not just what it is:

```dart
final r = flags.resolve(Flags.newCheckout);
r.value;        // true
r.sourceId;     // 'remote' | 'override' | null (bundled default)
r.isOverridden; // this device is not seeing what the backend would give it
```

"Why is this flag on for me?" is the most common question about any flag
system, and a bare `bool` cannot answer it. `resolveAll()` feeds a debug panel
or attaches a flag snapshot to a crash report.

## Exposure

`onExposure` fires the first time each flag is read with a given value — once
per flag-and-value per session, not once per `build()`. Send it to analytics.

This is what makes an experiment measurable: without it you know who was
*bucketed*, which includes everyone who never reached the screen, and the
result is noise. It refires after a mid-session change, so a rollout that flips
a user is recorded.

## Overrides

`FlagOverrideStore` is in-memory by default. For persistence, inject a callback
rather than pulling a storage dependency into this package:

```dart
FlagOverrideStore(
  initial: jsonDecode(prefs.getString('flag_overrides') ?? '{}'),
  persist: (o) => prefs.setString('flag_overrides', jsonEncode(o)),
  enabled: kDebugMode,   // never true in a release build
);
```

`enabled: false` makes the store have no opinion at all, so an override a
developer forgot about cannot ship to users.

## Adding a backend

Extend `FlagSourceBase`, implement `id` and `read`, and override `refresh` /
`changes` as the backend allows. Keep `read` free of I/O — it runs in `build()`.
