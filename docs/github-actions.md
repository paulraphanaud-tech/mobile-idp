# GitHub Actions

`scripts/generate-github-actions.sh` renders `templates/github/` into an app
repo. The `generate-github-actions` skill drives it conversationally, and the
`connect-app` skill uses it to take an app from "just written in a Claude chat"
to "compiled, tested and runnable" without anyone's own computer.

## Workflows

| File (in the app) | Trigger | Runner | Needs | Tier |
|---|---|---|---|---|
| `ios-ci.yml` | push, any branch; manual | macOS | nothing | 1 |
| `ios-preview.yml` | push to default branch; manual | macOS | nothing | 1 |
| `distribute.yml` (native) | manual only (`environment`, `destination` = testflight/firebase, `bump`) | macOS | GitHub environment secrets — or OIDC infra (below) | 2 |
| `distribute.yml` (Flutter) | manual only (`android` = firebase/none, `ios` = testflight/firebase/none) | Linux + macOS | GitHub environment secrets | 2 |
| `signing-setup.yml` | manual only | macOS (+ Linux for the Android key) | GitHub environment secrets | 2 |
| `flutter-ci.yml` | push, any branch; manual | Linux | nothing | 1 |
| `flutter-preview.yml` | push to default branch; manual | Linux | nothing | 1 |
| `flutter-ios-preview.yml` | push to default branch; manual | macOS | nothing | 1 |
| `.github/dependabot.yml` | monthly | — | keeps action versions current | — |

Design choices worth keeping:

- **CI listens to `push` only.** With `pull_request` as well, every PR runs
  twice. On a private repo macOS minutes count 10x against the free quota
  (2,000 → ~200 macOS minutes on GitHub Free), so duplicates are expensive.
  Every job has a `timeout-minutes` and a `cancel-in-progress` concurrency group.
- **CI uses `xcodebuild` directly**, not fastlane: no Ruby setup, no IDP
  checkout, nothing to sign — the fastest path to a red/green signal.
- **The simulator is picked at run time** (newest iOS runtime, first iPhone),
  so runner image updates don't break a hard-coded device name.
- **Test results** go to the job summary (`xcresulttool`); the `.xcresult`
  bundle is attached only on failure.

## Preview builds

`ios-preview.yml` builds an unsigned Debug simulator `.app`, zips it and
attaches it to the run. No secrets, no Apple account, no third-party service.
Install it on any Mac with `xcrun simctl install booted <App>.app`; to put the
app on a real iPhone, use `distribute.yml` (TestFlight or Firebase) — see
**`docs/github-distribution.md`** for the whole no-computer setup.

### Flutter previews

Same idea for Flutter, one workflow per platform:

- `flutter-preview.yml` — `flutter build apk --debug` on Linux (1x minutes).
  The APK is attached to the run, so it can also be installed straight onto an
  Android phone from the Actions page.
- `flutter-ios-preview.yml` — `flutter build ios --simulator --debug` on macOS,
  zipped `Runner.app` attached to the run.

An app written in
a Claude chat often has only `lib/` and `pubspec.yaml`: when
`android/app/build.gradle[.kts]` or `ios/Runner.xcodeproj` is missing, the job
runs `flutter create --platforms=<p> --org <org> .` for that build only and
commits nothing back. Commit the generated folder once you need to customise
it (permissions, icons, bundle ID).

Defaults: the generator picks `ios-preview` when the app has an `ios/` folder,
`preview` when it has `android/` or neither. Monorepos are supported: the app
directory is detected (the only Flutter-app `pubspec.yaml` outside
`packages/` and `example/`) or passed with `--app-dir`, and every job runs from
it. `flutter-ci.yml` skips `flutter test` when there is no `test/*_test.dart`
rather than failing.

## Distribution: GitHub secrets or AWS

`distribute.yml` and `signing-setup.yml` read credentials from **GitHub
environment secrets** by default — no AWS account, nothing to run on a
computer. That path, the secrets it needs and the one-time signing setup are
in **`docs/github-distribution.md`**. Certificates live in a private git
repository (`SIGNING_REPO`) with Match's git storage; the Android upload key is
kept, encrypted, in the same repository (`scripts/android-signing.sh`).

`ios-testflight.yml` from earlier versions is replaced by `distribute.yml`;
`--workflows testflight` still renders it.

## TestFlight without static credentials (AWS mode)

When the GitHub environment has an `AWS_ROLE_ARN` variable, the iOS job of
`distribute.yml` instead assumes that AWS role through GitHub OIDC, reads
`<env>/fastlane/credentials` with `aws-secretsmanager-get-secrets`, and leaves
Match storage to `fastlane/env.<env>` (S3 or git) — the same setup as a
CodeBuild stack. Android distribution always uses the GitHub secrets.

Infra (in the IDP stack of that environment):

```hcl
# infra/environments/dev/terraform.tfvars
github_actions_repositories = ["owner/app"]
# github_actions_environments = ["dev"]       # default: [environment]
# github_oidc_provider_arn    = "arn:aws:iam::…:oidc-provider/token.actions.githubusercontent.com"
#                                             # only if the provider already exists in the account
```

`make infra-plan ENV=dev`, then the user runs `make infra-apply ENV=dev`
(gated). `make infra-output ENV=dev` prints `github_actions_role_arn`.

The role (`modules/terraform/github_oidc`) trusts only
`repo:<owner>/<app>:environment:<env>` — jobs that declare that GitHub
environment — and can only `GetSecretValue` on the two fastlane secrets and
read the match bucket. Put required reviewers on the GitHub `prod` environment
to keep a human in front of production uploads.

In the app repo: Settings → Environments → `dev` → variable `AWS_ROLE_ARN`.
Set `APPLE_TEAM_ID` in `fastlane/env.dev`, and create the App Store Connect
record once (`make create-app`, gated — or in the App Store Connect web UI).

## Regenerating

Re-run the generator with `--force`. Action versions are pinned in one place
at the top of the script; dependabot bumps generated files in between.
