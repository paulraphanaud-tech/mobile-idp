# idp_analytics

Vendor-neutral analytics facade. The app depends on **this package only**;
vendors arrive as separate packages implementing `AnalyticsSink`.

## Why a facade

Calling `FirebaseAnalytics.instance.logEvent(...)` from a widget couples every
screen to one vendor, puts consent enforcement at thousands of call sites, and
lets an uninitialised SDK take a screen down. This package fixes all three in
one place.

## Composition

```dart
final analytics = Analytics(
  sinks: [
    if (kDebugMode) ConsoleAnalyticsSink(),
    FirebaseAnalyticsSink(),          // package:idp_analytics_firebase
    // AmplitudeSink(),               // adding a vendor is one line here
  ],
  onError: (e, s, {sinkId, operation}) =>
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'analytics/$sinkId'),
);
```

## Consent

`Analytics` enforces consent once, centrally:

| State | Behaviour |
|---|---|
| `unknown` | Events are **buffered** (bounded, oldest kept) and replayed if consent is granted. |
| `granted` | Events flow to every sink. |
| `denied` | Events are dropped. Moving granted → denied also calls `reset()` on every sink. |

`unknown` is deliberately not `denied`. Everything that happens between app
start and the user answering the prompt — which is most of a first session —
would otherwise be lost.

## Events

Prefer generated typed events over `logRaw`:

```dart
await analytics.log(CheckoutStarted(cartValue: 42, currency: 'EUR'));
```

`idp_codegen` generates one class per entry in `analytics/events.yaml`, so an
event name cannot be misspelled at a call site and renaming one is a compiler
error rather than a silent gap in a dashboard.

## Guarantees

- **Never throws.** Failures go to `onError`; a broken sink cannot crash a screen.
- **Isolated sinks.** One vendor failing does not stop the others.
- **Concurrent fan-out.** A slow vendor does not delay a fast one, but the
  returned future completes when all have settled, so tests can `await`.

## Testing

```dart
final sink = MemoryAnalyticsSink();
final analytics = Analytics(sinks: [sink], consent: Consent.granted);
// ... exercise the code under test
expect(sink.eventNames, ['checkout_started']);
```

## Adding a vendor

Extend `AnalyticsSinkBase` (not `AnalyticsSink` directly — the base class
no-ops every member, so methods added in a later version will not break your
adapter) and override only what the vendor supports. See
`../idp_analytics_firebase` for the worked example.
