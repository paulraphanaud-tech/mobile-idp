---
name: generate-github-actions
description: Generate GitHub Actions workflows for an app onboarded on the mobile IDP — simulator CI, preview builds attached as artifacts, signed test builds to TestFlight / Firebase App Distribution, and the one-time signing setup, for native iOS/SwiftUI and Flutter. Use when asked to add, regenerate or update CI/GitHub Actions for an app repo.
---

# Generate GitHub Actions workflows

The generator is `scripts/generate-github-actions.sh` in the mobile-idp repo.
It is deterministic: you choose options, it renders `templates/github/`. Do not
hand-write workflow YAML — if a template is missing a capability, change the
template in mobile-idp so every app gets it.

## 1. Locate things

- **App repo**: the directory you will run the script from (its root).
- **IDP**: a checkout of `paulraphanaud-tech/mobile-idp` (public). If you are
  inside mobile-idp, it is the repo root; otherwise clone it to a scratch
  directory outside the app repo, e.g. `git clone --depth 1
  https://github.com/paulraphanaud-tech/mobile-idp /tmp/mobile-idp`.

## 2. Choose options (detect first, ask only what you cannot detect)

| Option | How to decide |
|---|---|
| `--type` | `pubspec.yaml` (root, or a nested Flutter app) → `flutter`; an `*.xcodeproj` → `ios-native`. `.idp.env` records it after bootstrap. |
| `--workflows` | ios-native: `ci` (always), `preview` (default on), `distribute` + `signing` (when the user wants builds on a phone; `testflight` is an alias of `distribute`). flutter: `ci`, `preview` (Android APK, Linux), `ios-preview` (simulator, macOS), `distribute` + `signing`; default picks previews from the `ios/` / `android/` folders present. `distribute`/`signing` need the fastlane files the bootstrap scripts write. |
| `--app-dir` | flutter only. Detected: `.` if `./pubspec.yaml`, else the only Flutter-app pubspec outside `packages/`/`example/`. Pass it when there are several. |
| `--org` | flutter only. Org for `flutter create` when a platform folder is missing in CI; default `ORG` from `.idp.env`, else `com.example`. |
| `--signing-key-id` | flutter `distribute`/`signing`: which Android key in the signing repo. Default from `.idp.env`. Must be the same in both workflows. |
| `--build-only` | Open `<proj>.xcodeproj/xcshareddata/xcschemes/<scheme>.xcscheme`. If `<TestAction>` has no `<TestableReference>`, pass `--build-only`, otherwise `xcodebuild test` fails with "not configured for the test action". |
| `--default-branch` | `git symbolic-ref refs/remotes/origin/HEAD` or the GitHub API; default `main`. Previews run on pushes to it. |
| `--runner`, `--xcode` | Defaults `macos-latest` / `latest-stable`. Pin only if the project needs a specific Xcode (e.g. `objectVersion = 77` needs Xcode 16+). |
| `--timeout` | Default 30. It caps cost: macOS minutes count 10x against a private repo's free quota (2,000 → ~200 macOS minutes). |

Without `.idp.env`, prefer running `scripts/bootstrap-ios-native.sh` or
`scripts/bootstrap-flutter-github.sh` (they also write the Fastlane files the
distribute/signing workflows need, and then call this generator).

## 3. Render

```bash
bash <idp>/scripts/generate-github-actions.sh --type ios-native --workflows ci,preview --dry-run   # show
bash <idp>/scripts/generate-github-actions.sh --type ios-native --workflows ci,preview             # write
```

Existing files are skipped; pass `--force` only when the user asked to
regenerate. Then lint:

```bash
pip install --break-system-packages -q actionlint-py 2>/dev/null || pip install -q actionlint-py
actionlint .github/workflows/*.yml
```

## 4. Tell the user what each workflow needs

| Workflow | Needs | Cost/risk |
|---|---|---|
| `ios-ci.yml` | Nothing. Runs on every push. | Tier 1. ~5–10 macOS minutes per run. |
| `ios-preview.yml` | Nothing. Attaches the zipped simulator `.app` to the run. | Tier 1. Runs on the default branch + manually. |
| `distribute.yml` | A GitHub environment (`dev`…) with the secrets in `docs/github-distribution.md` step 5, a one-time `signing-setup.yml` run, and for TestFlight an App Store Connect app record. Alternatively, for iOS, an `AWS_ROLE_ARN` variable and the IDP's OIDC infra (`docs/github-actions.md`). | Tier 2: consumes a build number forever. Manual trigger only. |
| `signing-setup.yml` | Same GitHub environment; `SIGNING_REPO_TOKEN` with Contents write. | Tier 2: may create an Apple distribution certificate. Manual only. |
| `flutter-ci.yml` | Nothing. Linux runner. | Tier 1. |
| `flutter-preview.yml` | Nothing. Attaches the debug APK (installable on an Android phone). | Tier 1. Linux. Default branch + manual. |
| `flutter-ios-preview.yml` | Nothing. Attaches the zipped simulator `Runner.app`. | Tier 1. macOS (10x on private repos). Default branch + manual. |

## Rules

- Never create, set or print secrets (`gh secret set`, Secrets Manager). Tell
  the user which ones to add and where.
- Never trigger `distribute.yml` or `signing-setup.yml` on your own initiative.
- Never run Tier 3 IDP commands (`make infra-apply`, `make create-app`); hand
  them to the user — see CLAUDE.md "Blast radius and confirmation gates".
- Commit workflows on a branch, not straight to the default branch, unless the
  user says otherwise.
