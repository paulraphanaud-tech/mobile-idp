# idp_analytics_firebase

Firebase Analytics (GA4) binding for [`idp_analytics`](../idp_analytics).

```dart
Analytics(sinks: [FirebaseAnalyticsSink()]);
```

Requires `Firebase.initializeApp()` to have completed first.

## What this package is for

It is the platform's **worked example of a vendor adapter**. Adding Amplitude,
PostHog or Mixpanel later means writing a sibling of `lib/src/firebase_sink.dart`
and adding one line at composition — no screen in the app changes.

Copy its shape:

1. `extends AnalyticsSinkBase`, so members added to `AnalyticsSink` in a later
   version do not break you.
2. Override only what the vendor supports. `flush()` is deliberately left as
   the inherited no-op here, because Firebase Analytics has no flush API and a
   faked one would invite tests that depend on nothing.
3. Enforce the vendor's constraints **in the adapter**, not in the facade —
   GA4's 40-character event names and reserved `firebase_`/`google_`/`ga_`
   prefixes are GA4's problem, and applying them to every vendor would drop
   events that another backend accepts happily.
4. Report what you refuse, via `onDropped`. Firebase applies these limits
   silently; a truncated or rejected event is otherwise invisible until someone
   notices a dashboard is wrong weeks later.

## Consent

`setConsent` maps the facade's `Consent` onto Firebase consent mode **and**
calls `setAnalyticsCollectionEnabled`. Both are needed: consent mode alone
still permits cookieless pings, and only the second actually stops traffic.
