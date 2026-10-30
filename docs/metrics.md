# Metrics

This platform ships clear paths — `make build-android`, `make
deploy-ios-testflight`, `scripts/bootstrap.sh`. What it has not had is any way
to tell whether those paths are actually making delivery faster. This document
proposes the first four things to measure and how to collect them.

The goal is a next step that is obvious, not a dashboard. Two of the four are
implemented; two need a decision before they can be.

## What is instrumented today

`scripts/build-metrics.sh` runs in both buildspecs — `start` as the first
install command, `finish <platform>` as the last `post_build` command, so it
records failed builds too. It emits two metrics to the CloudWatch namespace
`MobileIDP` (configurable via `var.metrics_namespace`; set it to `""` to
disable and drop the IAM permission with it):

| Metric | Unit | Dimensions |
|---|---|---|
| `BuildDurationSeconds` | Seconds | Project, Platform, Environment, Status |
| `LeadTimeSeconds` | Seconds | Project, Platform, Environment, Status |

Both are also printed to the build log as `[metrics] BuildDurationSeconds=…`,
so they are queryable through CloudWatch Logs Insights even with metrics
disabled.

Instrumentation never fails a build. Every failure path in the script warns
and exits 0 — an observability problem must not become a delivery problem.

## The four metrics

### 1. Build duration — **implemented**

*Wall-clock time from the start of the install phase to the end of
post_build, per platform.*

The most direct feedback loop the platform has. It tells you whether a change
to the buildspec helped or hurt, and it is the number that decides whether
iOS needs a larger Mac fleet. Split by `Status` so a fast failure is not
mistaken for a fast build.

```
Namespace  MobileIDP
Metric     BuildDurationSeconds
Statistic  p50 and p95, not average — build time is long-tailed and the
           average hides the builds people actually complain about
```

### 2. Lead time, merge to distributable artifact — **implemented**

*Commit timestamp of `HEAD` to the moment the build finished.*

The DORA metric that matters most here, and the one the platform is supposed
to improve: how long a merged change waits before a tester could install it.
Computed as `now - git show -s --format=%ct HEAD`, which on a
merge-triggered pipeline is merge-to-artifact.

Caveat worth knowing before trusting the number: CodeBuild clones with
`git_clone_depth = 1`. HEAD's own timestamp is present, so the metric is
correct, but anything needing real history (time from *first* commit on a
branch, for example) is not available without deepening the clone.

This currently measures lead time to a *built artifact*, not to a *deployed*
one. Extending it to deployment is a matter of calling `build-metrics.sh
finish` after the deploy lane rather than after the build — a small change,
deliberately not made yet because it changes what the existing series means.

### 3. Deploy frequency — **not implemented; needs a decision**

*How many builds per week actually reach testers or a store.*

The collection is easy: a `DeployCount` metric with a `Target` dimension
(`firebase` / `testflight` / `play`), emitted from the deploy lanes in
`modules/fastlane/*_deploy_*`.

The decision is what counts as a deploy. Firebase App Distribution to an
internal group is not comparable to a TestFlight submission, and averaging
them produces a number that goes up when nothing improves. **Recommendation:**
count them as separate series from the start and never sum them.

### 4. Time to first successful build for a new project — **not implemented; needs a decision**

*From `scripts/bootstrap.sh` finishing to that project's first green build.*

This is the real measure of whether the IDP is doing its job. It is also the
hardest to collect honestly, because the interesting part happens outside any
system that is currently observing: waiting on an Apple Developer account,
chasing someone for a Team ID, finding out the CodeStar connection needs a
click in a console.

Two options, and they measure different things:

- **Timestamp-based.** `bootstrap.sh` writes its completion time into the
  generated repo; the first successful build emits
  `TimeToFirstBuildSeconds`. Cheap and automatic, but it measures calendar
  time including nights, weekends and "waiting for Apple" — likely a number in
  days that says more about Apple than about this platform.
- **Phase-based.** `bootstrap.sh` and the setup wizards record the duration of
  each step. More work, and needs the wizards to report, but it distinguishes
  *the platform is slow* from *the platform is waiting on a third party* —
  which is the distinction that tells you what to fix.

**Recommendation: phase-based**, and accept a smaller sample. A wrong number
here is worse than no number, because it drives effort at the wrong step.
This one is genuinely a decision, not an implementation detail.

## Collecting what already exists

Metrics (needs `cloudwatch:GetMetricStatistics`):

```bash
aws cloudwatch get-metric-statistics \
  --namespace MobileIDP \
  --metric-name BuildDurationSeconds \
  --dimensions Name=Platform,Value=ios Name=Environment,Value=dev \
  --start-time "$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time   "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 86400 --statistics Average Maximum \
  --region eu-west-1
```

(On Linux, `date -u -d '30 days ago'` instead of `date -u -v-30d`.)

From the logs, with no metric permissions at all:

```
fields @timestamp, @message
| filter @message like /\[metrics\] BuildDurationSeconds/
| parse @message "BuildDurationSeconds=* platform=* status=*" as secs, platform, status
| stats avg(secs), pct(secs, 95) by platform, status, bin(1d)
```

## Deliberately not done

- **No dashboard.** Two metrics do not justify one, and a dashboard built
  before anyone has asked a question of the data tends to answer none.
- **No alarms.** A "build got slower" alarm needs a baseline that does not
  exist yet. Collect for a few weeks first.
- **No cost metric.** The Mac fleet is reserved capacity and bills whether it
  builds or not, so build count is a poor cost proxy. Cost Explorer with the
  existing `Project` / `Environment` tags answers this better than a custom
  metric would.
