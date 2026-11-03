---
name: generate-github-actions
description: Generate GitHub Actions workflows for an app onboarded on the mobile IDP — simulator CI, browser previews (Appetize) and TestFlight for native iOS/SwiftUI, analyze+test for Flutter. Use when asked to add, regenerate or update CI/GitHub Actions for an app repo.
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
| `--type` | `pubspec.yaml` → `flutter`; an `*.xcodeproj` → `ios-native`. `.idp.env` records it after bootstrap. |
| `--workflows` | ios-native: `ci` (always), `preview` (default on), `testflight` (only if the user wants signed builds **and** the IDP infra has GitHub OIDC — see step 4). flutter: `ci`. |
| `--build-only` | Open `<proj>.xcodeproj/xcshareddata/xcschemes/<scheme>.xcscheme`. If `<TestAction>` has no `<TestableReference>`, pass `--build-only`, otherwise `xcodebuild test` fails with "not configured for the test action". |
| `--default-branch` | `git symbolic-ref refs/remotes/origin/HEAD` or the GitHub API; default `main`. Previews run on pushes to it. |
| `--runner`, `--xcode` | Defaults `macos-latest` / `latest-stable`. Pin only if the project needs a specific Xcode (e.g. `objectVersion = 77` needs Xcode 16+). |
| `--timeout` | Default 30. It caps cost: macOS minutes count 10x against a private repo's free quota (2,000 → ~200 macOS minutes). |

For ios-native without `.idp.env`, prefer running
`scripts/bootstrap-ios-native.sh` (it also writes the Fastlane files the
TestFlight workflow needs, and then calls this generator).

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
| `ios-preview.yml` | Optional secret `APPETIZE_API_TOKEN`; after first run, repo variable `APPETIZE_PUBLIC_KEY`. Without them it still attaches the zipped simulator `.app`. | Tier 1. Runs on the default branch + manually. |
| `ios-testflight.yml` | IDP infra with `github_actions_repositories = ["owner/repo"]` applied (Tier 3 gate — the **user** runs `make infra-apply`), a GitHub environment named like the IDP env with variable `AWS_ROLE_ARN`, Apple Team ID set in `fastlane/env.<env>`, an App Store Connect app record (`make create-app`, Tier 3), and populated `<env>/fastlane/credentials`. | Tier 2: consumes a build number forever. Manual trigger only. |
| `flutter-ci.yml` | Nothing. Linux runner. | Tier 1. |

## Rules

- Never create, set or print secrets (`gh secret set`, Secrets Manager). Tell
  the user which ones to add and where.
- Never trigger `ios-testflight.yml` on your own initiative.
- Never run Tier 3 IDP commands (`make infra-apply`, `make create-app`); hand
  them to the user — see CLAUDE.md "Blast radius and confirmation gates".
- Commit workflows on a branch, not straight to the default branch, unless the
  user says otherwise.
