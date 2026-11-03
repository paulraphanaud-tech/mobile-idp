---
name: connect-app
description: Connect an app repo (native iOS/SwiftUI or Flutter, often one just created in a Claude chat) to the mobile IDP and test it on GitHub-hosted runners — no personal computer or Mac needed. Bootstraps IDP files, generates GitHub Actions, pushes a branch, watches CI, fixes failures, reports results.
---

# Connect an app to the mobile IDP and test it in the cloud

Goal: the user built an app somewhere (typically a Claude chat, in a cloud
session with no Mac) and wants it compiled, tested and, ideally, runnable —
without touching their own computer. Everything below runs from a Linux shell
with `git` and `gh`; the macOS work happens on GitHub's runners.

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
bash /tmp/mobile-idp/scripts/bootstrap-ios-native.sh --workflows ci,preview [--build-only]
```

It detects project, scheme, bundle ID and team ID, writes `fastlane/`,
`Gemfile`, `Makefile`, `.idp.env`, `.gitignore` entries, then
`.github/workflows/ios-ci.yml` and `ios-preview.yml`. Check the scheme for a
test action first (see the `generate-github-actions` skill, `--build-only`).
Add `testflight` to `--workflows` only if the user asks for TestFlight.

**Flutter**: `scripts/bootstrap.sh` is interactive and provisions the full
CodeBuild pipeline — that is the `bootstrap` wizard, not this skill. For cloud
testing alone, run
`bash /tmp/mobile-idp/scripts/generate-github-actions.sh --type flutter`.
It finds the app directory (monorepos too; `--app-dir` if ambiguous) and
writes `flutter-ci.yml` plus a preview per platform present —
`flutter-ios-preview.yml` (macOS simulator build) and/or
`flutter-preview.yml` (Android debug APK on Linux; the default when the app
has no platform folders). Missing `ios/`/`android/` projects are generated in
CI by `flutter create`, so a chat-written app with only `lib/` works. If the
repo already has its own Flutter CI, pass `--workflows ios-preview` (or
`preview`) rather than duplicating it.

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
- **Run it without a Mac**:
  - Simulator build: `ios-preview.yml` attaches the zipped simulator `.app` to
    the run (pushes to the default branch, or manually from the Actions tab).
    No secrets needed.
  - Flutter: `flutter-ios-preview.yml` attaches the simulator build;
    `flutter-preview.yml` attaches a debug APK that installs directly on an
    Android phone.
  - iPhone: TestFlight via `ios-testflight.yml` — list the one-time
    prerequisites from the `generate-github-actions` skill (step 4).
- Open a PR with `gh api repos/<o>/<r>/pulls -f title=... -f head=idp/connect -f base=<base> -F body=@body.md`.

## Rules

- Never set secrets or variables for the user, never print secret values.
- Never dispatch `ios-testflight.yml` (Tier 2) or run Tier 3 IDP commands
  (`make infra-apply`, `make create-app`) on your own initiative.
- Don't push to the default branch unless asked.
