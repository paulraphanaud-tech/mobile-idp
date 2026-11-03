# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**This repository is the IDP (Internal Developer Platform) itself, not a
Flutter app.** It is the template and module source that *other* Flutter
projects consume. Nothing here builds an app on its own: `infra/environments/*`
and `templates/*` still contain unrendered `{{PLACEHOLDER}}` values, which
`scripts/bootstrap.sh` substitutes into a target project.

Layout:
- `modules/terraform/*` — reusable Terraform modules (s3, secrets, iam,
  codebuild, codepipeline, firebase)
- `modules/fastlane/*` — reusable Fastlane function modules, imported by a
  consuming project's Fastfile
- `modules/flutter/*` — Dart/Flutter packages the app depends on by path
  (analytics facade, feature-flag facade, their vendor adapters, and the
  registry code generator). See "Application platform" below.
- `infra/` — root Terraform config wiring the modules together
- `templates/` — files copied into a new project (Fastfile, Makefile,
  buildspecs, Gemfile, env files, tfvars)
- `scripts/bootstrap.sh` — renders templates into a new Flutter project, wires
  the Flutter packages into the project's pubspec, and runs the first codegen
- `.claude/commands/*` — conversational setup wizards that drive the above

The sections below describe the CI/CD system this platform *provisions* — i.e.
what a bootstrapped consumer project ends up with.

- **Firebase:** App Distribution for both platforms
- **Code signing (iOS):** Fastlane Match backed by a per-project S3 bucket
  (`<project>-match`)

## What "environment" means here

`ENV=dev|staging|prod` selects `infra/environments/<env>/{backend.tf,terraform.tfvars}`
and, through `var.environment`, the Secrets Manager path prefix. Investigated
rather than assumed, here is the **actual** isolation each boundary gives you:

| Boundary | Isolated per environment? |
|---|---|
| Terraform state | **Yes** — separate `key` in `backend.tf` (`<env>/terraform.tfstate`). |
| Secrets Manager paths | **Yes** — `<env>/fastlane/config`, `<env>/fastlane/credentials`, `<env>/android/signing`, `<env>/android/play_store`. |
| Git branch built, manual approval | **Yes** — `branch` and `enable_approval` per tfvars. |
| AWS account | **No.** One account. `providers.tf` has no `assume_role`; nothing switches accounts per environment. |
| GCP / Firebase project | **No.** All three tfvars carry the same `gcp_project_id`, so all environments register apps in one Firebase project. |
| AWS resource names (buckets, IAM roles, CodeBuild projects, Mac fleet, CodeStar connection) | **Only if you opt in.** `include_environment_in_resource_names` defaults to `false`, which means names are `<project>-*` in every environment — so two environments in one account **collide** and the second apply fails on duplicate S3 bucket / IAM role names. Set it to `true` at creation time to get `<project>-<env>-*`. |
| Signing material (match certs, Android keystore) | **No.** Shared, because the buckets are shared under the default naming. Even with the suffix on, the *Apple* certificates and the Android upload key are properties of the app identity, not the environment — separate them by using different bundle IDs / package names per environment, not by Terraform naming. |

So today, out of the box, dev/staging/prod are **separate state, separate
secrets, separate branch — one account, one Firebase project, one set of
resources**. That is enough to run *one* environment at a time cleanly; it is
not enough to run several side by side until
`include_environment_in_resource_names` is turned on.

The stronger boundary, if it matters, is one AWS account per environment, at
which point identical resource names are fine and the flag stays `false`.
That is a follow-up, not implemented.

## Secrets

Four AWS Secrets Manager paths hold everything CI needs. **`docs/secrets.md`**
is the reference: what each path contains, blast radius if leaked, rotation
cadence, and why the App Store Connect / Firebase / Play credentials cannot be
natively auto-rotated.

- `make secrets-audit ENV=<env>` — read-only; reports each secret's age
  against its recommended cadence and flags any that Terraform created but
  nobody populated.
- **No static AWS credentials exist anywhere in this platform.** Builds use
  the CodeBuild service role's temporary credentials; there is no IAM user,
  access key, or `aws configure` in either buildspec. Keep it that way — if
  something needs new AWS permissions, add them to the role in
  `modules/terraform/iam/main.tf`.
- Agents must never populate a secret on the user's behalf, and must never
  echo a secret value into the transcript.

## Supply chain: SBOM and dependency scanning

Both buildspecs run `scripts/supply-chain.sh` (steps: `install`, `sbom`,
`scan`, plus `upload` in `post_build`). Per build, per platform, it produces:

| File | What it is |
|---|---|
| `<platform>-sbom.cdx.json` | CycloneDX SBOM generated by **syft** from the source tree — the resolved dependency tree (`pubspec.lock`, `Gemfile.lock`, `Podfile.lock`, Gradle caches), not the shrunk binary |
| `<platform>-sbom.txt` | The same, as a readable table |
| `<platform>-vulns.json` | **osv-scanner** report against the OSV database |
| `<platform>-vulns.txt` | The same, as a readable table |

**Where to find them after a build**, in order of convenience:

1. **S3** — `s3://<project>-artifacts/supply-chain/<platform>/<build-id>/`.
   Keyed by `CODEBUILD_BUILD_ID`, so nothing is overwritten and a report
   traces back to its build. Uploaded in `post_build`, so it exists even when
   the build failed.
2. **Build log** — the scan prints a severity breakdown and the top 25
   findings inline in CloudWatch.
3. **Locally** — `build/supply-chain/` in the build workspace.

**Configuration** (CodeBuild environment variables, all with defaults):

| Variable | Default | Meaning |
|---|---|---|
| `SC_ENABLED` | `true` | Master switch |
| `SC_FAIL_ON` | `none` | Severity at or above which findings fail the build: `none` / `low` / `moderate` / `high` / `critical` / `any` |
| `SYFT_VERSION`, `OSV_SCANNER_VERSION` | empty (latest) | Pin for reproducible tooling |
| `SC_OUT_DIR`, `SC_TOOL_DIR` | `build/supply-chain`, `$HOME/.sc-tools` | Paths |

`SC_FAIL_ON` defaults to `none` — report, don't block. This is a template
other teams inherit, and a scanner that fails their build on day one over an
untriaged transitive advisory gets switched off entirely. Raise it once a
baseline is clean. **Picking the real threshold belongs to the team owning the
app, not to a default this platform imposes.**

Behaviour worth knowing:

- The scan runs **before** the build on both platforms — a critical advisory
  should stop the build, not be found after an APK exists.
- With `SC_FAIL_ON=none`, a scanner that fails to install warns and continues.
  With anything else, a scanner that could not run **fails the build** —
  silently shipping unscanned code is what enforcement exists to prevent.
- Findings with no parsable severity are reported as `unknown` and are **not**
  counted against the threshold; the scan says so explicitly when any exist.
  Severity comes from GitHub advisories' `database_specific.severity` or a
  numeric CVSS v3 score; full CVSS vector parsing is not implemented.
- **CocoaPods is a known gap.** osv-scanner has no CocoaPods ecosystem, so iOS
  native pods appear in the SBOM but are not vulnerability-scanned. Dart, Ruby
  and Gradle dependencies are covered on both platforms.

### S3 bucket hardening

All three buckets (`modules/terraform/s3`) already have versioning,
`aws_s3_bucket_public_access_block` with all four flags true, and
`aws_s3_bucket_server_side_encryption_configuration` with AES256 — verified,
nothing was missing. Not present, and a reasonable next step: a bucket policy
denying `aws:SecureTransport = false`.

## Application platform: analytics, feature flags, design system

Three capabilities that live in the *app* rather than the pipeline. Each is
driven by a registry file that is the single source of truth, with the
generated Dart committed alongside it.

| Registry | Generates | Reference |
|---|---|---|
| `flags/flags.yaml` | `lib/generated/flags.g.dart` + the published flag document | **`docs/feature-flags.md`** |
| `analytics/events.yaml` | `lib/generated/events.g.dart` — one class per event | **`docs/analytics.md`** |
| `design/tokens.json` | `lib/generated/design_tokens.g.dart` — `ThemeData` + `ThemeExtension`s | **`docs/design-system.md`** |

`make codegen` regenerates all three. Both buildspecs run
`scripts/codegen.sh validate` and `scripts/codegen.sh check` before the build:
validate lints the registries, check fails when a registry was edited without
regenerating. Without the second, the build compiles the *old* generated code
and passes, which is the expensive failure mode.

### The shape, and why

Every vendor sits behind a facade in `modules/flutter/idp_analytics` /
`idp_feature_flags`, which have **no vendor dependencies at all**. Adding
Amplitude next to Firebase, or swapping Remote Config for the AWS backend, is a
new adapter package plus one line at composition — no call site in the app
changes. The adapters shipped:

| Package | Backend |
|---|---|
| `idp_analytics_firebase` | Firebase Analytics (GA4). The worked example of a vendor binding. |
| `idp_analytics_flutter` | Navigator observer + `AnalyticsScope`. Vendor-neutral. |
| `idp_feature_flags_firebase` | Firebase Remote Config |
| `idp_feature_flags_aws` | A document on S3 behind CloudFront, targeting evaluated on device |

Two properties are load-bearing and should survive any refactor:

- **Neither facade ever throws.** An uninitialised vendor SDK, an offline
  device, or a backend returning `"maybe"` for a boolean produces a bundled
  default and an entry in the error hook — never an exception in `build()`.
- **Flag reads are synchronous.** Flags are read inside `build()`; making them
  async turns every flagged widget into a `FutureBuilder` with a loading state.
  Sources keep an in-memory snapshot that `refresh()` updates.

The consequence to design for: **before the first fetch, every flag is its
bundled default.** Defaults must therefore be the safe value — for a kill
switch, "feature on, kill switch not pulled".

### Feature flag backends

`feature_flags_backend` in each environment's tfvars selects `none`, `aws` or
`firebase`. Both backends read the same `flags.yaml`.

**AWS is not AppConfig, deliberately.** AppConfig's data API is SigV4-signed,
so reaching it from a phone means shipping a Cognito identity pool that mints
AWS credentials for anyone who asks, and it bills per configuration request
with no CDN in front. `modules/terraform/feature_flags` instead publishes a
JSON document to S3 behind CloudFront: no AWS credentials in the binary, edge
cached, effectively free at any install base. Staged rollout comes from
client-side targeting in the document, which addresses *users* rather than
config propagation.

**Firebase Remote Config has one template per Firebase project.** All three
environments share one `gcp_project_id` by default, so under that backend
dev/staging/prod share one set of flag values and publishing `prod` overwrites
what `dev` published. Use separate Firebase projects, or the `aws` backend. The
renderer also refuses to translate `user_id` and `attributes` conditions rather
than translating them to something that targets different people.

### Flag debt

Every flag declares an `owner` and an `expires` date; missing either is a
validation warning. `make flags-audit` reports overdue flags and is read-only —
it never fails a build, because flag debt is a standing conversation rather
than a reason to block tonight's release.

## Build metrics

`scripts/build-metrics.sh` runs in both buildspecs (`start` first in `install`,
`finish <platform>` last in `post_build`, so failed builds are recorded too).
It emits `BuildDurationSeconds` and `LeadTimeSeconds` — commit timestamp to
build finish — to the CloudWatch namespace `MobileIDP`, dimensioned by
Project / Platform / Environment / Status, and prints both to the build log as
`[metrics] <Name>=<value>` so they are queryable via Logs Insights even
without metric permissions.

Set `var.metrics_namespace = ""` to disable: the CodeBuild role then gets no
`cloudwatch:PutMetricData` grant and the script skips publishing. The grant is
scoped by the `cloudwatch:namespace` condition key — `PutMetricData` is one of
the actions with no resource ARN, so `"*"` plus a condition is the tightest
form available.

Instrumentation never fails a build; every failure path warns and exits 0.

**`docs/metrics.md`** proposes the first four metrics to track and what is
still an open decision (what counts as a "deploy", and how to measure
time-to-first-successful-build honestly).

## Blast radius and confirmation gates

This platform is driven by AI agents through the `.claude/commands/*` wizards,
so every command has to be safe to *suggest*, not just safe to run. Commands
fall into three tiers.

### Tier 1 — Read-only. Safe to run freely, repeatedly, unattended.

| Command | Effect |
|---|---|
| `make infra-init` | Initializes the Terraform backend. Touches no resources. |
| `make infra-plan` | Writes and prints a saved plan. Changes nothing. |
| `make infra-output` | Reads state. |
| `make flutter-test` / `flutter-get` / `flutter-clean` | Local only. |
| `make build-android` / `build-ios` | Local build. Produces artifacts, ships nothing. |
| `make download-keystore` | Reads from S3. |
| `make sync-certs` / `sync-certs-appstore` with `readonly:true` | Reads Match state from S3. CI always uses `readonly:true` (see `buildspec_ios.yml`). |
| `bash scripts/setup.sh check` | Prerequisite check. |
| `make codegen` / `codegen-check` / `validate-registries` | Regenerates or checks `lib/generated/`. Local files only. |
| `make design-tokens` | Regenerates the theme from `design/tokens.json`. |
| `make flags-plan ENV=<env>` | Renders `flags.yaml` and diffs it against what the backend serves. Changes nothing. |
| `make flags-audit` | Flag debt report. |

### Tier 2 — Mutating but recoverable. No gate; think before running.

| Command | Effect | Recovery |
|---|---|---|
| `make infra-apply` | Creates/modifies AWS + Firebase resources. | Gated (see below). A wrong apply is fixed by another apply. |
| `make populate-secrets` | Overwrites all four Secrets Manager values. | Secrets Manager keeps prior versions (`AWSPREVIOUS`). |
| `make deploy-android-firebase` / `deploy-ios-firebase` | Publishes a build to testers. | Delete the release in the Firebase console. |
| `make deploy-ios-testflight` | Uploads a build to TestFlight. | Build can be expired, but the version/build number is consumed forever. |
| `make deploy-android-play-store` | Uploads to a Play track. | Halt the rollout; the version code is consumed forever. |
| `make upload-keystore` | Overwrites `keystore/release-key.jks` in S3. | Bucket is versioned — restore the prior version. |
| `make flags-publish ENV=dev\|staging` | Changes flag values for that environment. | Republish, or restore the prior S3 object version. Non-prod, so blast radius is testers. |
| `make sync-certs` **without** `readonly:true` | Match may *create or revoke* Apple certificates. | Revoking a cert breaks every build using it until re-synced. Prefer `readonly:true`. |

### Tier 3 — Destructive or irreversible. Gated by `scripts/confirm.sh`.

| Command | Gate phrase | Why |
|---|---|---|
| `make infra-destroy ENV=<env>` | `destroy <project>-<env>` | Deletes CodeBuild projects, the reserved-capacity Mac fleet, CodePipeline, IAM roles, the CodeStar connection, and Secrets Manager entries. S3 buckets use `force_destroy = false`, so destroy **fails** while match/keystore buckets hold objects — signing material is not silently deleted, but everything else goes. |
| `make infra-apply ENV=<env>` | `apply <env>` | Gated not because apply is destructive, but because a *plan* can be: replacement of `aws_s3_bucket.match` or `aws_s3_bucket.keystore` destroys signing material. The gate forces the plan to be read first. |
| `make create-app` | `create <bundle-id>` | App Store Connect records **cannot be deleted**, and the app name is globally unique across Apple's entire store — a wrong name is permanently burned for everyone. |
| `make flags-publish ENV=prod` | `publish flags prod` | The fastest path to production there is: a flag change reaches installed apps within the CDN TTL, with no build, no review and no app store. It *is* recoverable — the bucket is versioned and Remote Config keeps template history — but users see it first, which is why it is gated rather than merely mutating. |
| `make generate-keystore` | `generate keystore <env>` | A new upload key for an already-published app makes every future Play upload fail with "not signed by the upload key". Only a Play support key reset recovers it. The lane additionally refuses to overwrite an existing keystore file unless `KEYSTORE_OVERWRITE=true`. |

### How the gates work

`scripts/confirm.sh "<phrase>" "<warning>"...` prints the warning, then
requires the exact phrase — typed on `/dev/tty` by a human, or supplied as
`CONFIRM="<phrase>"`. A generic `yes` is deliberately not accepted: the bypass
cannot be produced without naming the specific thing being destroyed.

`make infra-apply` additionally depends on `infra-plan`, so the full plan is
always printed, unpiped and untruncated, immediately above the prompt; the
saved plan file is what gets applied, so what runs is exactly what was
reviewed. `AUTO_APPROVE=1` skips only the prompt, and exists for pipelines.

### Rules for agents

1. **Never run a Tier 3 command on your own initiative.** Surface it as a step
   for the user and let them run it.
2. **Never publish flags to prod on your own initiative**, and never answer
   its gate. `make flags-plan ENV=prod` is read-only and is the right thing to
   run and show instead.
3. **Never set `CONFIRM` or `AUTO_APPROVE`.** Filling in a gate on the user's
   behalf is the exact failure mode these gates exist to prevent. If a gate
   blocks you, report the prompt and wait.
4. **Never `terraform destroy`** — not to clean up a failed apply, not to get
   to a clean state, not because a resource already exists. A failed apply is
   fixed by fixing the config and applying again.
5. **Never hide plan output.** Don't pipe `terraform plan` through `head`,
   `tail`, or `grep`, and don't summarise it instead of showing it. Before
   asking for approval, state the add/change/destroy counts and name every
   resource marked for destruction or replacement.
6. **Get explicit approval per apply.** An earlier "go ahead" given before the
   plan existed does not cover the plan you are now looking at.

## Common Commands

Everything is driven through the Makefile; `make help` lists the targets with
their gates. `ENV` selects the environment and defaults to `dev`.

```bash
make help                              # Targets, with gates called out
bash scripts/setup.sh check            # Verify local tooling

# Infrastructure
make infra-init  ENV=dev               # One-time, per environment
make infra-plan  ENV=dev               # Read-only; prints the full plan
make infra-apply ENV=dev               # Plans, shows it, then gates on 'apply dev'
make infra-output ENV=dev

# Secrets
make populate-secrets ENV=dev          # Interactive; writes to <env>/... paths
make secrets-audit    ENV=dev          # Read-only age / staleness report

# Registries: flags, analytics events, design tokens
make codegen                           # Regenerate lib/generated/ from all three
make codegen-check                     # CI guard: fails if generated code is stale
make validate-registries               # Lint the registries without generating
make flags-audit                       # Flags past their expiry date (read-only)
make flags-plan    ENV=dev             # Diff flags.yaml against the live backend
make flags-publish ENV=dev             # Publish; ENV=prod gates on 'publish flags prod'
make design-tokens                     # Regenerate the theme

# Build and deploy (run from a bootstrapped project, not this repo)
make build-android ENV=dev BUMP=patch
make build-ios     ENV=dev BUMP=patch
make deploy-android-firebase ENV=dev
make deploy-android-play-store ENV=prod TRACK=internal
make deploy-ios-firebase   ENV=dev
make deploy-ios-testflight ENV=prod

# Signing
make sync-certs ENV=dev                # Match, development certs
make sync-certs-appstore ENV=dev       # Match, App Store certs
make create-app ENV=dev APP_NAME="My App"   # GATED — irreversible
make generate-keystore ENV=dev              # GATED — irreversible
make upload-keystore ENV=dev
```

Note this repo itself has no Flutter app: `flutter build`, `flutter test` and
the deploy targets only do anything in a project produced by
`scripts/bootstrap.sh`.

## Architecture

### Onboarding a new project

`scripts/bootstrap.sh`, run from the target Flutter project's root, renders
`templates/` into it: Fastfile, Matchfile, Pluginfile, `env.dev`,
`env.secret.example`, Gemfile, Makefile, both buildspecs, `infra/*.tf`,
`infra/environments/{dev,staging,prod}/{terraform.tfvars,backend.tf}`, the three
registries (`flags/flags.yaml`, `analytics/events.yaml`, `design/tokens.json`),
the composition root `lib/idp.dart`, and `scripts/{codegen,flags}.sh`. The IDP
modules are wired in either as a git submodule at `ci-cd/` or copied to
`modules/`; `{{MODULES_PATH}}` in the generated Fastfile and in
`scripts/codegen.sh` points at whichever was chosen.

Bootstrap additionally inserts the `modules/flutter/*` packages as `path`
dependencies into the project's `pubspec.yaml`, excludes the modules directory
from `analysis_options.yaml` (otherwise `flutter analyze` descends into
packages resolved elsewhere and reports hundreds of phantom errors), and runs
the first codegen. The registries and `lib/idp.dart` are **never overwritten**
on a re-run — they are files the team owns. The `.claude/commands/*` wizards walk a human through the same
decisions conversationally.

### CI/CD flow

`CodePipeline` (Source → Build_Android → Build_iOS → optional Approval) is
triggered by a CodeStar Connections GitHub source. Each build stage runs a
CodeBuild project:

- **Android** — `buildspec.yaml`, Linux (`amazonlinux-x86_64-standard:5.0`,
  `BUILD_GENERAL1_LARGE` — MEDIUM's 3GB gets the Gradle daemon OOM-killed
  mid-`assembleRelease`). Installs the Android SDK and Flutter, downloads the
  keystore from S3, runs `fastlane android build_deploy`.
- **iOS** — `buildspec_ios.yml`, on a reserved-capacity **Mac fleet**
  (`aws_codebuild_fleet.mac`, `MAC_ARM`) — macOS CodeBuild has no on-demand
  compute. Most of that buildspec is keychain and TLS workarounds for the
  CodeBuild macOS image; each one carries a comment explaining what failed
  without it. Read those before editing.

Secrets reach both builds as CodeBuild project environment variables of type
`SECRETS_MANAGER`, defined in `infra/main.tf` — **not** in the buildspecs. See
the Secrets section above for why.

### Terraform modules (`modules/terraform/`)

| Module | Creates |
|---|---|
| `s3` | Three buckets — match certs, Android keystores, pipeline artifacts. All versioned, SSE-AES256, public access blocked, `force_destroy = false`. |
| `secrets` | The four Secrets Manager entries, empty, 7-day recovery window. |
| `iam` | CodeBuild and CodePipeline service roles. No IAM users, no access keys. |
| `codebuild` | The Android and iOS projects plus the Mac fleet. |
| `codepipeline` | The pipeline and its stages. |
| `firebase` | Registers the Firebase Android and iOS apps on a GCP project. |
| `feature_flags` | The flag bucket and its CloudFront distribution, with origin access control, a short-TTL cache policy and a bucket policy that denies non-TLS access. Created only when `feature_flags_backend = "aws"`. |

`infra/` wires them together. Resource names come from `local.name_prefix`
(see the environment section above).

### Fastlane modules (`modules/fastlane/`)

Each file defines plain Ruby functions, no lanes — the consuming project's
Fastfile imports them and wraps them in lanes, so lane names stay the
project's own. Functions: `prepare_and_check`, `compute_next_version`
(`common`), `build_android` / `build_ios`, `deploy_android_to_app_distrib` /
`deploy_ios_to_app_distrib`, `deploy_android_to_play_store`,
`deploy_ios_to_app_store_connect`, `sync_certificates` (`match_s3`),
`create_app_on_asc` (`produce`), the `keystore` trio, and `dart_defines`
(`common`), which forwards `FLAGS_URL` / `FLAGS_BACKEND` / `ENVIRONMENT` into
the build as `--dart-define`. Only non-secret identifiers belong there: a
`--dart-define` is embedded in the binary in clear text and is trivially
recoverable from a downloaded APK.

Two auth paths, deliberately different: everything except app-record
creation uses the **App Store Connect API key** — including the bundle ID
registration `create_app_on_asc` does first (`POST /v1/bundleIds`, skipped if
the identifier exists). The app record itself needs an **Apple ID web
session** (`FASTLANE_USER`/`PASSWORD`/`SESSION` from `spaceauth`), because
Apple's public API has no app-creation endpoint. The session lasts ~30 days,
which is why `create_app` is a developer-machine action, not a CI one.

### Environment configuration (in a bootstrapped project)

- `fastlane/env.<env>` — non-secret config: `FLAVOR`, `SCHEME`, Firebase App
  IDs, `APP_IDENTIFIER`, `MATCH_S3_BUCKET`, `S3_KEYSTORE_BUCKET`, `AWS_REGION`,
  `FLAGS_BACKEND`, `FLAGS_URL`
- `fastlane/env.secret` — local-only credentials, gitignored. In CI these come
  from Secrets Manager instead; the Fastfile's `before_all` skips the file
  when `CI` or `CODEBUILD_BUILD_ID` is set.
- Selected by `FASTLANE_ENV`, which the Makefile sets from `ENV`.

### Projects without flavors, single-platform projects

- **No flavors.** Leave `FLAVOR` (and `SCHEME`) empty in `fastlane/env.<env>`.
  `build_ios` then runs `flutter build ios --release` without `--flavor`, uses
  the plain `Release` configuration, scheme `Runner` and
  `ios/export_options.plist`, and writes `build/ios/ipa/app-release.ipa`
  (`ios_ipa_path`). `update_code_signing_settings` sets the bundle ID on
  `Release`, so Flutter's placeholder ID cannot leak into the IPA.
  The Android modules still assume a flavor.
- **One platform.** The `firebase` Terraform module skips the Android app when
  `android_package_name = ""` and the iOS app when `ios_bundle_id = ""`. Its
  outputs are then `null`. `moved` blocks keep existing projects' apps at
  their old state addresses, so upgrading the module plans no replacement.

### Versioning

Semantic `major.minor.patch` with the build number fetched from Firebase App
Distribution and incremented. `BUMP=patch|minor|major` chooses the segment;
`version:` pins an explicit one.

### Signing

- **Android** — keystore in the `<prefix>-keystores` bucket, downloaded at
  build time; passwords from `<env>/android/signing`.
- **iOS** — Fastlane Match with S3 storage in the `<prefix>-match` bucket,
  encrypted with `MATCH_PASSWORD`. CI always runs Match `readonly:true` so a
  build can never create or revoke a certificate.
