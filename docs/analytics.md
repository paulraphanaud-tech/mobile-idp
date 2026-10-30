# Analytics

`analytics/events.yaml` is the source of truth. `make codegen` turns it into
one Dart class per event.

```dart
await analytics.log(CheckoutStarted(
  cartValue: 42.0,
  currency: 'EUR',
  itemCount: 3,
));
```

## Why a registry and a facade

Three problems with `FirebaseAnalytics.instance.logEvent(name: 'checkout_strted')`
scattered through the widget tree, and this platform's answer to each:

| Problem | Answer |
|---|---|
| A misspelled name is a silent gap in a dashboard nobody notices for weeks | Events are generated classes. A typo does not compile. |
| Consent enforcement lands at thousands of call sites | `Analytics` enforces it once, centrally. |
| Adding a second vendor is a migration | Vendors are sinks. Adding one is a line at composition. |

An escape hatch exists — `analytics.logRaw('name', {...})` — and is deliberately
uglier than the generated call so it stands out in review.

## Declaring an event

```yaml
events:
  - name: checkout_started      # snake_case, <= 40 chars
    description: User tapped the checkout call to action.
    owner: payments
    parameters:
      - name: cart_value
        type: double            # string | int | double | bool
        required: true
      - name: coupon_code
        type: string            # optional
```

Optional parameters are **omitted** from the payload rather than sent as null.
Vendors disagree about what a null means, and some store the literal string
`"null"`.

## Limits are checked at build time

`make analytics-validate` holds the registry to GA4's limits, because GA4
enforces them by *silently dropping* what breaks them:

- event name: snake_case, ≤ 40 characters
- the `firebase_`, `google_` and `ga_` prefixes are reserved — events using
  them are never recorded
- names GA4 already collects (`session_start`, `first_open`, `app_update`, …)
  are rejected: sending your own mixes hand-rolled data into a series the
  platform also writes, and the two cannot be separated afterwards
- ≤ 25 parameters per event; parameter names ≤ 40 characters

Both buildspecs run this before the build.

These are GA4's limits, not universal ones. They live in the registry check and
in the Firebase adapter — **not** in the facade, because applying one vendor's
limits to every vendor would drop events another backend accepts happily.

## Composition

```dart
Analytics(
  sinks: [
    if (kDebugMode) ConsoleAnalyticsSink(),
    FirebaseAnalyticsSink(),
    // AmplitudeSink(...),   <- a second vendor goes here, not at call sites
  ],
  onError: (e, s, {sinkId, operation}) =>
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'analytics/$sinkId'),
);
```

Guarantees:

- **Never throws.** An uninitialised, offline or mid-upgrade vendor SDK cannot
  take a screen down. Failures go to `onError`.
- **Isolated sinks.** One vendor failing does not stop the others.
- **Concurrent fan-out.** A slow vendor does not delay a fast one, but the
  returned future completes when all have settled, so tests can `await`.

## Consent

Enforced in `Analytics`, once:

| State | Behaviour |
|---|---|
| `unknown` | Buffered (bounded, oldest kept) and replayed if consent is granted |
| `granted` | Delivered to every sink |
| `denied` | Dropped. granted → denied also calls `reset()` on every sink |

`unknown` is deliberately not `denied`. Everything between app start and the
user answering the prompt — most of a first session, including `app_opened` —
would otherwise be lost.

Withdrawal calls `reset()` because it means the vendor should forget the
identifiers it already holds, not merely stop receiving new ones.

`reset()` on logout runs regardless of consent: clearing state must never be
gated on a permission, or a denied user inherits a granted user's identifiers.

## Personal data

Do not put personal data in event parameters. They land in GA4 and BigQuery,
are retained on the vendor's schedule rather than yours, and cannot be
selectively deleted for one user afterwards. Use a user id for identity and
keep attributes non-identifying.

This is a convention the platform documents and does not enforce — a
`pii: true` marker in the registry would be a lint, not a guarantee, and the
real check is review.

## Adding a vendor

Write a sibling of `modules/flutter/idp_analytics_firebase/lib/src/firebase_sink.dart`:

1. `extends AnalyticsSinkBase`, so members added to `AnalyticsSink` later do
   not break the adapter.
2. Override only what the vendor supports. Firebase Analytics has no flush API,
   so `flush()` is left as the inherited no-op rather than faked.
3. Enforce the vendor's own constraints in the adapter.
4. Report what you refuse, via a callback. Vendors apply limits silently.

Then add it to the `sinks:` list. No screen changes.

## Screen views

```dart
MaterialApp(navigatorObservers: [AnalyticsNavigatorObserver(analytics)]);
```

Vendor-neutral, so every sink gets the screen view — Firebase's own
`FirebaseAnalyticsObserver` reports to Firebase alone, which silently gives a
second vendor no screen data.

The default extractor **skips routes with no name**, which is what dialogs,
bottom sheets and anonymous `MaterialPageRoute`s usually are. Reporting those
as screens inflates screen counts and corrupts per-screen engagement time.

## Testing

```dart
final sink = MemoryAnalyticsSink();
final analytics = Analytics(sinks: [sink], consent: Consent.granted);
// ... exercise the code under test
expect(sink.eventNames, ['checkout_started']);
```

No vendor SDK, no mocking framework, no platform channels.
