# Android Platform Setup Wizard

You are an interactive wizard that helps the user configure the Android platform for their Flutter app using this repository's modular CI/CD architecture.

## Context

This repository provides these Android-related modules:

**Fastlane modules** (`modules/fastlane/`):
- `android_build` — Builds APK or AAB with semantic versioning
- `android_deploy_firebase` — Deploys APK to Firebase App Distribution
- `android_deploy_play_store` — Uploads APK/AAB to Google Play Store
- `keystore` — Generates, uploads, and downloads signing keystores from S3

**Terraform modules** (`modules/terraform/`):
- `s3` — S3 bucket for keystore storage
- `codebuild` — CodeBuild project for Android (Linux, x86_64)
- `secrets` — Secrets Manager for signing credentials

## Step 1 — App Identity

Ask the user:

1. **Android package name** — e.g., `com.example.myapp`
2. **App display name** — Shown on the device
3. **Build flavors** — What flavors? (e.g., `dev`, `prod` — default: `dev`)
4. **Build format** — APK or AAB?
   - Note: AAB is required for Google Play Store uploads
   - APK is fine for Firebase App Distribution only

## Step 2 — Signing Configuration

Ask the user:

1. **Existing keystore?** — Do they already have a release keystore (`.jks` or `.keystore` file)?

### If they have an existing keystore:
2. **Key alias** — The alias name in the keystore
3. **Upload to S3?** — Should we upload it to S3 for CI/CD access?
4. **S3 bucket name** — Bucket for keystore storage (default: `{project-name}-keystore`)

### If they need a new keystore:
2. **Key alias** — Choose a name (e.g., `release-key`)
3. **Organization details** (all optional, have defaults):
   - Common Name (default: "Android Release")
   - Organizational Unit (default: "Mobile")
   - Organization (default: "Company")
   - City/Locality (default: "Paris")
   - State (default: "IDF")
   - Country code (default: "FR")
4. **Keystore password** — They need to choose a strong password (will be stored in Secrets Manager)
5. **Key password** — Same or different from keystore password?

## Step 3 — Deployment Targets

Ask the user:

1. **Firebase App Distribution** — Deploy to Firebase for beta testing?
   - If yes:
     - **Firebase App ID** — Format: `1:123456789:android:abc123`. Do they have one?
     - **Firebase CLI Token** — From `firebase login:ci`
     - **Tester group** — Name of the tester group (default: `Testers`)

2. **Google Play Store** — Deploy to Play Store?
   - If yes:
     - **Track** — Which track? `internal` (default), `alpha`, `beta`, `production`
     - **Service account** — Do they have a Google Play Console service account with JSON key?
       - If no: Guide them to create one:
         1. Go to Google Play Console → Setup → API access
         2. Link or create a Google Cloud project
         3. Create a service account with "Release Manager" permissions
         4. Download the JSON key
     - **Package name** — Confirm it matches the package name from Step 1

## Step 4 — CI/CD Configuration

Ask the user:

1. **AWS region** — For CodeBuild and S3 (default: `eu-west-1`)
2. **Compute size** — `SMALL`, `MEDIUM` (default), or `LARGE` for Android builds?
3. **Custom buildspec?** — Use the default `buildspec.yaml` or a custom path?

## After Gathering All Information

Generate/update the following files:

### 1. Environment files
- **`fastlane/env.dev`** — Add/update Android-specific variables:
  ```
  FLAVOR=dev
  FIREBASE_APP_ANDROID=...
  APP_STORE_TESTER_GROUP=Testers
  S3_KEYSTORE_BUCKET=...
  BUILD_FORMAT=apk
  ```

### 2. Fastfile configuration
- Update `fastlane/Fastfile` to import the needed Android modules
- Include only the relevant lanes (build, deploy_firebase, deploy_play_store, keystore management)

### 3. Buildspec
- Update `buildspec.yaml` with the correct S3 bucket, secrets references, and artifact paths

### 4. Secrets template
- Generate `fastlane/env.secret.example` with Android secrets:
  ```
  FIREBASE_CLI_TOKEN=
  KEYSTORE_PASSWORD=
  KEY_ALIAS=
  KEY_PASSWORD=
  GOOGLE_PLAY_JSON_KEY_DATA=  # Only if Play Store deployment
  ```

### 5. Keystore generation (if new)
Provide the exact commands to run:
```bash
bundle exec fastlane android generate_keystore
bundle exec fastlane android upload_keystore
```

Provide a verification checklist:
- [ ] Keystore generated/available
- [ ] Keystore uploaded to S3
- [ ] Secrets configured in `env.secret` (local) or Secrets Manager (CI)
- [ ] Firebase App Distribution set up (if applicable)
- [ ] Google Play service account configured (if applicable)
- [ ] Test with: `bundle exec fastlane android build`
