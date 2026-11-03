# Test builds on your phone, from GitHub Actions only

From "an app written in a Claude chat" to "installed on my phone" with no
personal computer, no Mac and no AWS account. Everything runs on GitHub-hosted
runners. Everything you do yourself happens in a browser, and a phone browser
is enough.

| App | Android | iOS |
|---|---|---|
| Flutter | Firebase App Distribution | TestFlight, or Firebase App Distribution |
| Native iOS (Swift/SwiftUI) | — | TestFlight, or Firebase App Distribution |

```
app repo ── bootstrap (agent) ──► fastlane/ + .github/workflows/
                                      │
   GitHub environment "dev"           │  you, once: secrets + "Signing setup"
   (secrets, SIGNING_REPO) ───────────┤
                                      ▼
        Actions → "Distribute to testers" → Run workflow
            ├─ Linux  : flutter build apk → re-sign → Firebase ──► tester's Android
            └─ macOS  : match (read-only) → archive → TestFlight / Firebase ──► iPhone
```

## 1. Connect the app (the agent does this)

From the app repo root, with mobile-idp cloned somewhere outside it:

```bash
bash /tmp/mobile-idp/scripts/bootstrap-flutter-github.sh   # Flutter
bash /tmp/mobile-idp/scripts/bootstrap-ios-native.sh       # native iOS (.xcodeproj)
```

This writes `fastlane/`, `Gemfile`, `.idp.env` and these workflows:

| Workflow | Trigger | Does | Tier |
|---|---|---|---|
| `flutter-ci.yml` / `ios-ci.yml` | every push | analyze + test / simulator tests | 1 |
| previews | push to main | debug APK / simulator build attached to the run | 1 |
| `signing-setup.yml` | manual | one-time: bundle ID, devices, certificates, profiles, Android key | 2 |
| `distribute.yml` | manual | signed build → Firebase / TestFlight | 2 |

Both bootstrap scripts print the identifiers they picked: the **iOS bundle ID**
and the **Android package**. You need them in steps 3 and 4. To change them,
edit `fastlane/env.dev` (`APP_IDENTIFIER`) and, for Android, commit an
`android/` folder with your own `applicationId`. Changing them after the first
distribution makes a new app as far as testers' phones are concerned.

## 2. A private signing repository (once, for all your apps)

Fastlane Match keeps the iOS certificates and profiles there, and the Android
upload key lives next to them. Everything is encrypted with `MATCH_PASSWORD`
before it leaves the runner.

1. GitHub → **New repository** → e.g. `<you>/mobile-signing`, **Private**,
   with a README (an empty repository also works).
2. GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate:
   - Repository access: **only** `mobile-signing`
   - Permissions: **Contents: Read and write** (the signing setup writes; builds only read)
   - Expiration: up to a year. Put the date in your calendar.
3. Pick a long random `MATCH_PASSWORD` and keep it in your password manager.
   Lose it and every certificate and key in the repo has to be re-issued. For
   Android that means testers reinstall the app.

## 3. Apple (iOS only)

Needs a paid Apple Developer Program membership.

1. **Team ID**: developer.apple.com → Account → Membership details. The agent
   puts it in `fastlane/env.dev` (`APPLE_TEAM_ID`).
2. **API key**: App Store Connect → Users and Access → **Integrations** → App
   Store Connect API → Team Keys → **+**. Role **Admin**, or **App Manager**
   with "Access to Certificates, Identifiers & Profiles". Note the **Key ID**
   and the **Issuer ID**. Download the `.p8` file: Apple lets you download it
   **once**. Open it as text and copy everything, from
   `-----BEGIN PRIVATE KEY-----` to the end line.
3. **App record** (TestFlight only): this comes *after* step 5, because the
   signing setup registers the bundle ID first. App Store Connect → Apps → **+
   New App** → iOS, any name, the bundle ID from step 1, SKU = the bundle ID.
   Apple has no API for this step. Note that an app name is unique across the
   whole App Store, permanently.
4. **Testers**: TestFlight → Internal Testing → **+** group → add people.
   Internal testers must be users of your App Store Connect team, which
   includes you. They get every build automatically.

## 4. Firebase (Android, and iOS via Firebase)

1. console.firebase.google.com → **Add project** (Analytics can stay off).
2. Add an **Android app** with the package name from step 1, and/or an **iOS
   app** with the bundle ID. Skip the config-file download, which the build
   doesn't need. The agent copies each **App ID** (`1:…:android:…`,
   `1:…:ios:…`) into `fastlane/env.dev`.
3. **App Distribution** → Get started → Testers & Groups → add a group whose
   **alias** is `testers` (or whatever `FIREBASE_TESTER_GROUPS` says) → add
   testers' emails.
4. **Service account**: console.cloud.google.com (same project) → IAM & Admin →
   Service Accounts → **Create** → role **Firebase App Distribution Admin** →
   Keys → Add key → **JSON**. Copy the whole JSON file content.

## 5. GitHub environment (the secrets)

App repo → Settings → **Environments** → New environment → `dev`:

| Name | Kind | Value | Needed for |
|---|---|---|---|
| `SIGNING_REPO` | variable | `<you>/mobile-signing` | everything |
| `SIGNING_REPO_TOKEN` | secret | token from step 2 | everything |
| `MATCH_PASSWORD` | secret | passphrase from step 2 | everything |
| `APP_STORE_CONNECT_API_KEY_ID` | secret | Key ID | iOS |
| `APP_STORE_CONNECT_ISSUER_ID` | secret | Issuer ID | iOS |
| `APP_STORE_CONNECT_API_KEY` | secret | full `.p8` text | iOS |
| `FIREBASE_SERVICE_ACCOUNT` | secret | full JSON key | Firebase |

You can skip what you don't use: an Android-only test needs the first three
plus Firebase. If something is missing, the first run fails and lists **every**
missing name, so it's safe to just try.

Environment secrets are only given to jobs that declare that environment. For
`prod`, add **Required reviewers** so a human approves every production
upload.

Then run **Actions → Signing setup → Run workflow** (`dev`). It:
- registers the bundle ID and creates the distribution certificate plus the
  App Store and ad-hoc profiles (iOS);
- creates the Android upload key (only if none exists; it never replaces one).

## 6. Distribute

**Actions → Distribute to testers → Run workflow**: pick the environment,
Android (`firebase`/`none`), iOS (`testflight`/`firebase`/`none`), and
optionally release notes. Each run bumps the version and consumes a build
number for good (Tier 2).

| Where | Tester installs with |
|---|---|
| Firebase, Android | the invitation email → **Firebase App Tester** app, or the web link. Allow "install unknown apps" once. |
| TestFlight | the **TestFlight** app, 5–15 min after the run while Apple processes the build. The first build of a new app may ask you to confirm export compliance in App Store Connect. |
| Firebase, iOS | the invitation email, opened **in Safari** on the iPhone → install the profile. The iPhone must be in the ad-hoc profile (below). |

### iPhones for Firebase (ad-hoc) builds

An ad-hoc build only installs on registered devices; TestFlight doesn't have
this limit. Accepting a Firebase invitation on an iPhone asks the tester to
share the device's UDID, and Firebase then emails it to you (App Distribution
→ Testers also shows it). Then re-run **Signing setup** with
`ios_devices` = `Paul iPhone=00008110-…; Anna=…`, and distribute again. Prefer
TestFlight for iOS unless you have a reason not to.

## Projects already on the CodeBuild pipeline

The workflows work with a project bootstrapped by `scripts/bootstrap.sh`:
`bootstrap-flutter-github.sh` keeps its existing `fastlane/` files and only adds
`.idp.env` and the workflows. Check these things:

- **Fastfile lanes**: `ios setup_signing` is new. Add it as in
  `templates/fastlane/Fastfile`. If the Fastfile imports modules from a
  submodule (`ci-cd/`), the workflows use that pinned copy, not `.idp/`, so
  update the submodule to a mobile-idp version that has this feature.
- **iOS signing source**: by default the workflows use git storage in
  `SIGNING_REPO`, overriding the env file's `MATCH_STORAGE_MODE=s3` (via
  `IDP_MATCH_*`). That's a *new* Match storage, so Signing setup creates a
  certificate (Apple allows a small number of distribution certificates per
  team). To keep the existing S3 storage instead, set the GitHub environment
  variable `AWS_ROLE_ARN` (docs/github-actions.md, "TestFlight without static
  credentials"). The iOS job then reads `<env>/fastlane/credentials` through
  OIDC and leaves storage to `fastlane/env.<env>`. The Android job always uses
  the signing repo.
- **Flavors**: `FLAVOR` in `fastlane/env.<env>` is honoured on both platforms.

## Costs and limits

- macOS minutes count **10x** against a private repo's free quota (GitHub
  Free: 2,000 min ≈ 200 macOS minutes). A Flutter iOS distribution takes
  roughly 15–25 min. Android runs on Linux at 1x.
- Apple caps distribution certificates per team. Signing setup reuses the one
  in `SIGNING_REPO`. Running it against a *new* signing repo creates another.
- Firebase App Distribution is free. Builds expire after 150 days.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Missing in this repository's GitHub environment" | Add the listed names (step 5). Secrets must be on the *environment*, not only on the repo, or on both. |
| `cannot read https://github.com/…` / match clone fails | `SIGNING_REPO` misspelled, or the token doesn't include that repository. |
| "push … failed" in Signing setup | Token lacks **Contents: write**. |
| "No Android key at android/…" | Run Signing setup with `android` ticked. |
| "Could not find App" / TestFlight upload rejected | Create the App Store Connect record (step 3.3). |
| "Maximum number of certificates" | Revoke an unused Apple Distribution certificate at developer.apple.com, or point `SIGNING_REPO` at the storage that already holds one. |
| iPhone says "Unable to install" (Firebase) | Device not in the ad-hoc profile: register it (above). |
| Android "App not installed" over a previous build | That build was signed with a different key (e.g. a debug APK from `flutter-preview.yml`). Uninstall once. |
| `APPLE_TEAM_ID is not set` | Fill it in `fastlane/env.<env>`. |

## What runs where

| Step | Code |
|---|---|
| Credentials → canonical env vars, missing-secret report | `scripts/ci-credentials.sh` |
| Gems on Linux/macOS from a Mac-written `Gemfile.lock` | `scripts/ci-bundle.sh` |
| Temporary keychain for match | `scripts/ci-keychain.sh` |
| Android upload key, create/fetch | `scripts/android-signing.sh` |
| Bundle ID, devices, `match` readonly:false | `setup_signing` in `modules/fastlane/match` |
| Builds and uploads | `modules/fastlane/{android_build,android_deploy_firebase,ios_build,ios_deploy_*,ios_native}` |
