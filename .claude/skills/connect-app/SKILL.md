---
name: connect-app
description: Connect an app repo (native iOS/SwiftUI or Flutter, often one just created in a Claude chat) to the mobile IDP, test it on GitHub-hosted runners and get signed test builds onto phones through Firebase App Distribution or TestFlight — no personal computer or Mac needed. Bootstraps IDP files, generates GitHub Actions, pushes a branch, watches CI, fixes failures, walks the user through the one-time signing/secrets setup, reports results.
---

# Connect an app to the mobile IDP and test it in the cloud

Goal: the user built an app somewhere (typically a Claude chat, in a cloud
session with no Mac) and wants it compiled, tested and installed on a phone —
without touching their own computer. Everything below runs from a Linux shell
with `git` and `gh`; the macOS work happens on GitHub's runners. The user's
part (accounts, secrets) is done in a browser and is described in
`docs/github-distribution.md` — read it before step 7.

## 0. Get both repos into the session

- **App repo** (`owner/app`) — needs push access. In a Claude cloud session,
  attach it with the `add_repo` tool (`access: "push"`) and clone it.
- **mobile-idp** (`paulraphanaud-tech/mobile-idp`, public) — read is enough.
  Clone it to a scratch dir **outside** the app repo, e.g. `/tmp/mobile-idp`.
  If the user is iterating on the IDP itself, use their branch (`--idp-ref`).
- In Claude cloud sessions `gh pr create` and other GraphQL calls are blocked;
  use REST (`gh api repos/<o>/<r>/...`) for everything below.

## 1. Branch

Work on `idp/connect` (or a name the user gives), branched from the branch
that holds the app code — which may not be the default branch if the app is
still in an open PR. Ask only if that is ambiguous.

## 2. Bootstrap

**Native iOS** (an `*.xcodeproj`, no `pubspec.yaml`):

```bash
cd <app>
bash /tmp/mobile-idp/scripts/bootstrap-ios-native.sh [--build-only] [--firebase-ios-app 1:…:ios:…]
```

It detects project, scheme, bundle ID and team ID, writes `fastlane/`,
`Gemfile`, `Makefile`, `.idp.env`, `.gitignore` entries, then
`.github/workflows/ios-ci.yml`, `ios-preview.yml`, `distribute.yml` and
`signing-setup.yml` (the last two are manual-only and need secrets — step 7).
Check the scheme for a test action first (see the `generate-github-actions`
skill, `--build-only`). If the user only wants CI, pass
`--workflows ci,preview`.

**Flutter**:

```bash
bash /tmp/mobile-idp/scripts/bootstrap-flutter-github.sh --org <reverse.domain> \
  [--bundle-id …] [--team-id …] [--firebase-android-app …] [--firebase-ios-app …]
```

Non-interactive, no AWS. It finds the app directory (monorepos too;
`--app-dir` if ambiguous), writes `fastlane/`, `Gemfile`, `.idp.env`, and the
workflows `flutter-ci.yml`, both previews, `distribute.yml`,
`signing-setup.yml`. Missing `ios/`/`android/` projects are generated in CI by
`flutter create`, so a chat-written app with only `lib/` works. Ask the user
for the org / bundle ID if the app is going to TestFlight: an App Store
bundle ID is hard to change later (the default `com.example` is a placeholder,
not an identity to ship under). Existing `fastlane/` files are kept (a CodeBuild-bootstrapped app);
read "Projects already on the CodeBuild pipeline" in
`docs/github-distribution.md` then. If the repo already has its own Flutter
CI, pass `--workflows ios-preview,preview,distribute,signing`.

`scripts/bootstrap.sh` (interactive, full CodeBuild pipeline on AWS) is the
`bootstrap` wizard, not this skill.

Lint: `pip install -q actionlint-py && actionlint .github/workflows/*.yml`.

## 3. Push

```bash
git checkout -b idp/connect
git add -A && git commit -m "Connect to mobile IDP: fastlane + GitHub Actions"
git push -u origin idp/connect
```

If the push is rejected because the token lacks the `workflow` scope, stop and
tell the user: the GitHub connection used by this session cannot write
`.github/workflows/`. They can re-authorise it, or commit the generated files
themselves via the GitHub web UI.

## 4. Watch CI

```bash
gh api "repos/<o>/<r>/actions/runs?branch=idp/connect&per_page=5" \
  --jq '.workflow_runs[] | {id, name, status, conclusion, html_url}'
```

Poll every ~60 s (a cold macOS run takes 5–15 min). When a run completes:

```bash
gh api repos/<o>/<r>/actions/runs/<run_id>/jobs --jq '.jobs[] | {id, name, conclusion, steps: [.steps[] | select(.conclusion=="failure") | .name]}'
gh api repos/<o>/<r>/actions/jobs/<job_id>/logs > /tmp/job.log    # follows the redirect
grep -nE "error:|\*\* (BUILD|TEST) FAILED|Testing failed|failed \(" /tmp/job.log | head -50
```

## 5. Fix loop

On failure, read the errors, fix the **app code** (or the generator options,
e.g. `--build-only`), commit, push, watch again. Cap it at 3 attempts without
progress and then report — each run costs macOS minutes. Never weaken a test
to make it pass; if a test is wrong, say so explicitly.

## 6. Report

- CI result and the run URL; test counts from the job summary.
- **Run it without a Mac, right now** (no secrets):
  - `flutter-preview.yml` attaches a debug APK that installs directly on an
    Android phone.
  - `ios-preview.yml` / `flutter-ios-preview.yml` attach a simulator build —
    useful on a Mac only; an iPhone needs step 7.
- Open a PR with `gh api repos/<o>/<r>/pulls -f title=... -f head=idp/connect -f base=<base> -F body=@body.md`.
  `distribute.yml` and `signing-setup.yml` are `workflow_dispatch` only, and
  GitHub only offers a dispatchable workflow once the file is on the
  **default branch** — so they become usable when that PR is merged.

## 7. Installable builds (Firebase / TestFlight)

Hand the user a checklist built from `docs/github-distribution.md`, filled in
with this app's values (bundle ID and Android package from the bootstrap
output, the repo's Settings → Environments URL). Only the parts they need:

| They want | Steps of the doc |
|---|---|
| Android via Firebase | 2 (signing repo), 4 (Firebase), 5 (secrets) |
| iPhone via TestFlight | 2, 3 (Apple), 5 |
| iPhone via Firebase | 2, 3.1–3.2, 4, 5, plus device UDIDs |

Things you do, not them:
- Put the values they send you that are **not secret** — Apple Team ID,
  Firebase App IDs, tester group alias — into `fastlane/env.dev`, commit, push.
  Anything else they paste to you (keys, tokens, passwords) — tell them to put
  it in the GitHub environment instead and not to share it in chat.
- When they say the secrets are in place **and ask you to**, dispatch the
  workflows through the REST API and watch them like step 4:

```bash
gh api repos/<o>/<r>/actions/workflows/signing-setup.yml/dispatches \
  -f ref=<default-branch> -f 'inputs[environment]=dev'
gh api repos/<o>/<r>/actions/workflows/distribute.yml/dispatches \
  -f ref=<default-branch> -f 'inputs[environment]=dev' -f 'inputs[ios]=testflight'   # Flutter
#   native: -f 'inputs[destination]=testflight'
```

A first run that fails in the **Credentials** step lists every missing secret
by name — relay that list. For TestFlight, remind them to create the App Store
Connect record after the signing setup has registered the bundle ID (doc step
3.3); the upload fails with "Could not find App" until then.

## Rules

- Never set secrets or variables for the user, never print secret values, and
  never ask for secret values in chat.
- Never dispatch `distribute.yml` or `signing-setup.yml` (Tier 2) or run Tier 3
  IDP commands (`make infra-apply`, `make create-app`) on your own initiative.
  "Set it up so I can test on my phone" is consent to step 7's checklist, not
  to dispatching; dispatch when the user asks for a build.
- Don't push to the default branch unless asked.
