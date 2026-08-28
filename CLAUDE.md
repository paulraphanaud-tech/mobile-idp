# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter mobile app with Fastlane CI/CD automation targeting both Android and iOS. Builds are deployed to Firebase App Distribution (beta) or Apple TestFlight (production). CI/CD runs on AWS CodeBuild.

- **App ID (iOS):** fr.ippon.fastlane-ci-cd
- **Team ID:** 254M6TE7EY
- **Firebase:** App Distribution for both platforms
- **Code signing (iOS):** Fastlane Match backed by S3 bucket `flutter-aws-match`

## Common Commands

### Local development
```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Fastlane (always use `bundle exec`)
```bash
# Android
bundle exec fastlane android build                            # Build APK
bundle exec fastlane android build_deploy                     # Build + deploy to Firebase

# iOS
bundle exec fastlane ios build                                # Build IPA
bundle exec fastlane ios deploy target:app_distrib            # Deploy to Firebase
bundle exec fastlane ios deploy target:app_store_connect      # Deploy to TestFlight (default)

# Optional params: version:1.2.0 bump:patch|minor|major
```

### Manual Flutter builds
```bash
flutter clean && flutter pub get
flutter build apk --flavor dev --release
flutter build ios --release --no-codesign
```

## Architecture

### CI/CD Flow
- **`buildspec.yaml`** — AWS CodeBuild for Android: installs Flutter + Android SDK, downloads keystore from S3, runs `fastlane android build_deploy`
- **`buildspec_ios.yml`** — AWS CodeBuild for iOS: installs Flutter, runs `fastlane ios deploy` with `TARGET` and `BUMP` env vars
- AWS Secrets Manager injects credentials at build time (paths: `dev/` and `prod/`)

### Fastlane (`fastlane/Fastfile`)
Key helper functions called by lanes:
- `prepare_and_check()` — `flutter clean` + `flutter pub get`
- `compute_next_version()` — semantic version bump logic
- `build_android()` / `build_ios()` — platform build helpers
- `deploy_android_to_app_distrib()` / `deploy_ios_to_app_distrib()` — Firebase deployment
- `deploy_ios_to_app_store_connect()` — TestFlight deployment via `pilot`

### Environment configuration
- **`fastlane/env.dev`** — non-sensitive config: `FLAVOR`, `SCHEME`, Firebase App IDs, `MATCH_S3_BUCKET`, `AWS_REGION`
- **`fastlane/env.secret`** — sensitive credentials (not committed): Firebase CLI token, App Store Connect API key, Android keystore credentials
- Load with `--env dev` or set `FASTLANE_ENV=dev` in CI

### Versioning
Semantic versioning (major.minor.patch) with auto-incremented build numbers fetched from Firebase App Distribution. The `bump` lane parameter controls which segment increments.

### Android signing
Keystore stored base64-encoded in S3, downloaded and decoded at build time in `buildspec.yaml`. Keystore credentials come from Secrets Manager / `env.secret`.

### iOS signing
Fastlane Match (S3 storage) manages certificates and provisioning profiles. Export options defined in `ios/export_options_dev.plist`. Minimum iOS version: 15.6.

### Firebase integration
- `firebase.json` maps platform targets to Firebase projects
- `lib/firebase_options.dart` contains platform-specific Firebase config
- Android: `android/app/google-services.json`
- Plugin: `fastlane-plugin-firebase_app_distribution` (see `fastlane/Pluginfile`)
