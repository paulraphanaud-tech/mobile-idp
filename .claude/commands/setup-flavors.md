# Flutter Flavor Setup Wizard

You are an interactive wizard that creates and configures build flavors (environments) for a Flutter mobile application, targeting both Android and iOS platforms.

## Your Role

Guide the user step-by-step through setting up flavors. Ask questions ONE GROUP AT A TIME. Wait for answers before proceeding. Be conversational and explain what each step does. Actively verify the project state before making changes.

This skill can be used standalone (`/setup-flavors`) or invoked from the bootstrap wizard (`/bootstrap`).

---

## Step 0 — Project Detection & Current State

Before asking any questions, silently detect the project context:

### Detect target project
1. Check if `pubspec.yaml` exists in the current directory — if yes, this is the target Flutter project.
2. If not, ask the user for the Flutter project path.
3. Read `pubspec.yaml` to get the project name and current configuration.

### Detect platforms
1. Check if `android/app/build.gradle.kts` or `android/app/build.gradle` exists (Kotlin DSL vs Groovy).
2. Check if `ios/Runner.xcodeproj/project.pbxproj` exists.
3. Report which platforms are available.

### Detect existing flavors
1. **Android**: Parse `build.gradle.kts` (or `.gradle`) for existing `productFlavors` block. List any flavors already defined.
2. **iOS**: Check `ios/Runner.xcodeproj/xcshareddata/xcschemes/` for existing scheme files. Parse `project.pbxproj` for build configurations matching `Debug-*`, `Release-*`, `Profile-*` patterns.
3. **Fastlane**: Check `fastlane/env.*` files (excluding `env.secret` and `env.secret.example`) to see which environment files exist.

### Report current state
Display a summary like:
```
Project: my_app (from pubspec.yaml)
Platforms: Android + iOS

Existing flavors detected:
  Android: dev (in build.gradle.kts productFlavors)
  iOS:     dev (scheme: dev.xcscheme, configs: Debug-dev, Release-dev, Profile-dev)
  Fastlane: env.dev

Bundle ID / Package Name:
  Android: com.example.myapp (from build.gradle.kts defaultConfig.applicationId)
  iOS:     com.example.myapp (from project.pbxproj PRODUCT_BUNDLE_IDENTIFIER)
```

Ask: **"Do you want to add new flavors, modify existing ones, or start fresh?"**

---

## Step 1 — Flavor Definition

Ask the user:

1. **Flavor names** — Which flavors do you want? Common patterns:
   - `dev` + `prod` (simple, recommended for most apps)
   - `dev` + `staging` + `prod` (with a staging/QA environment)
   - Custom names
   
   Default: `dev`, `prod`

2. **For each flavor**, collect:

   | Setting | Example (dev) | Example (staging) | Example (prod) |
   |---------|--------------|-------------------|-----------------|
   | Display name | MyApp Dev | MyApp Staging | MyApp |
   | Bundle ID suffix | `.dev` | `.staging` | _(none)_ |
   | App icon distinction? | Yes (debug banner) | Yes (staging banner) | No |

3. **Base bundle ID / package name** — What is the base identifier? (e.g., `com.company.myapp`)
   - Dev flavor becomes: `com.company.myapp.dev`
   - Staging flavor becomes: `com.company.myapp.staging`
   - Prod flavor keeps: `com.company.myapp`

4. **Firebase per flavor?** — Do they have separate Firebase projects/apps per flavor?
   - If yes: collect Firebase App IDs per flavor per platform
   - If no: same Firebase config for all flavors (or no Firebase)

5. **Separate entry points?** — Do they want per-flavor Dart entry points? (e.g., `lib/main_dev.dart`, `lib/main_prod.dart`)
   - If yes: we'll create them with flavor-specific configuration
   - If no: single `lib/main.dart` with runtime flavor detection

---

## Step 2 — Android Flavor Setup

**Only if Android platform is detected.**

### 2a. Detect build script type

Check if the project uses `build.gradle.kts` (Kotlin DSL) or `build.gradle` (Groovy). Adapt the generated code accordingly.

### 2b. Modify `android/app/build.gradle.kts` (or `.gradle`)

Add or update the `productFlavors` block inside the `android {}` block.

**For Kotlin DSL (`build.gradle.kts`):**

```kotlin
flavorDimensions += "env"
productFlavors {
    create("dev") {
        dimension = "env"
        applicationIdSuffix = ".dev"
        resValue("string", "app_name", "MyApp Dev")
    }
    create("staging") {
        dimension = "env"
        applicationIdSuffix = ".staging"
        resValue("string", "app_name", "MyApp Staging")
    }
    create("prod") {
        dimension = "env"
        resValue("string", "app_name", "MyApp")
    }
}
```

**For Groovy (`build.gradle`):**

```groovy
flavorDimensions "env"
productFlavors {
    dev {
        dimension "env"
        applicationIdSuffix ".dev"
        resValue "string", "app_name", "MyApp Dev"
    }
    staging {
        dimension "env"
        applicationIdSuffix ".staging"
        resValue "string", "app_name", "MyApp Staging"
    }
    prod {
        dimension "env"
        resValue "string", "app_name", "MyApp"
    }
}
```

### 2c. Update `AndroidManifest.xml` (if using resValue for app_name)

If the user wants per-flavor app names via `resValue`, update `android/app/src/main/AndroidManifest.xml`:
- Change `android:label="..."` to `android:label="@string/app_name"` in the `<application>` tag.

### 2d. Firebase per flavor (Android)

If the user has separate Firebase configs per flavor:

1. Create flavor-specific source directories:
   ```
   android/app/src/dev/google-services.json
   android/app/src/staging/google-services.json
   android/app/src/prod/google-services.json
   ```
2. Move the existing `android/app/google-services.json` to the appropriate flavor directory.
3. Explain that each `google-services.json` must match the flavor's `applicationId` (with suffix).

If NOT using per-flavor Firebase:
- Keep a single `android/app/google-services.json`
- Warn that the `package_name` in `google-services.json` must match the default `applicationId` or be registered for all flavor variants in the Firebase console.

### 2e. Signing config per flavor (optional)

Ask: "Do you want different signing configurations per flavor?"
- If yes (common pattern: debug keystore for dev, release keystore for prod):
  ```kotlin
  signingConfigs {
      create("release") {
          storeFile = file(System.getenv("KEYSTORE_PATH") ?: "release.keystore")
          storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
          keyAlias = System.getenv("KEY_ALIAS") ?: ""
          keyPassword = System.getenv("KEY_PASSWORD") ?: ""
      }
  }
  
  buildTypes {
      release {
          signingConfig = signingConfigs.getByName("release")
      }
  }
  ```
- If no: keep the current signing config

---

## Step 3 — iOS Flavor Setup

**Only if iOS platform is detected.**

iOS flavors in Flutter require 3 things per flavor:
1. Build configurations: `Debug-{flavor}`, `Release-{flavor}`, `Profile-{flavor}`
2. An Xcode scheme referencing those configurations
3. An export options plist for archive/distribution

### 3a. Build Configurations in `project.pbxproj`

For each NEW flavor (skip flavors that already have configurations):

**Important**: Modifying `project.pbxproj` directly is complex and error-prone. Instead, use the following approach:

1. **Recommend using Xcode** for adding build configurations:
   - Open `ios/Runner.xcodeproj` in Xcode
   - Go to Project → Info → Configurations
   - For each flavor, duplicate:
     - `Debug` → `Debug-{flavor}`
     - `Release` → `Release-{flavor}`
     - `Profile` → `Profile-{flavor}`

2. **Or use `xcodeproj` Ruby gem** (if available) to automate it. Check with:
   ```bash
   gem list xcodeproj
   ```
   If available, generate a Ruby script that:
   - Opens the Xcode project
   - Duplicates the base configurations for each flavor
   - Sets the correct `PRODUCT_BUNDLE_IDENTIFIER` per flavor config (base ID + suffix)
   - Sets `PRODUCT_NAME` and `MARKETING_VERSION` as needed
   - Saves the project

   ```ruby
   require 'xcodeproj'
   
   project_path = 'ios/Runner.xcodeproj'
   project = Xcodeproj::Project.open(project_path)
   
   flavors = {
     'dev' => { bundle_suffix: '.dev', display_name: 'MyApp Dev' },
     'staging' => { bundle_suffix: '.staging', display_name: 'MyApp Staging' },
     'prod' => { bundle_suffix: '', display_name: 'MyApp' },
   }
   
   base_bundle_id = 'com.company.myapp'
   
   flavors.each do |flavor, config|
     ['Debug', 'Release', 'Profile'].each do |base_config_name|
       config_name = "#{base_config_name}-#{flavor}"
       
       # Skip if already exists
       next if project.build_configurations.any? { |c| c.name == config_name }
       
       # Find base configuration
       base_config = project.build_configurations.find { |c| c.name == base_config_name }
       next unless base_config
       
       # Duplicate for each target's build configuration list
       project.native_targets.each do |target|
         target_base = target.build_configurations.find { |c| c.name == base_config_name }
         next unless target_base
         
         new_config = target.add_build_configuration(config_name, target_base.type)
         new_config.build_settings = target_base.build_settings.clone
         
         if target.name == 'Runner'
           bundle_id = base_bundle_id + config[:bundle_suffix]
           new_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
         end
       end
       
       # Also duplicate project-level configuration
       project_base = project.build_configuration_list.build_configurations.find { |c| c.name == base_config_name }
       if project_base
         new_project_config = project.build_configuration_list.build_configurations.new(config_name)
         new_project_config.build_settings = project_base.build_settings.clone
       end
     end
   end
   
   project.save
   ```

3. **Or manually edit `project.pbxproj`** as a last resort:
   - This approach should duplicate existing build configuration blocks and add references to the `XCConfigurationList` sections.
   - Only do this if both Xcode and xcodeproj gem are unavailable.
   - When editing the pbxproj, generate unique 24-character hex IDs for each new entry (use `SecureRandom.hex(12)` pattern).

### 3b. Create Xcode Schemes

For each flavor, create a scheme file at `ios/Runner.xcodeproj/xcshareddata/xcschemes/{flavor}.xcscheme`.

Use the existing scheme as a template (e.g., `dev.xcscheme` or `Runner.xcscheme`), and replace:
- `buildConfiguration` references: `Debug-{flavor}`, `Release-{flavor}`, `Profile-{flavor}`
- Keep the `BuildableReference` pointing to `Runner.xcodeproj` and `Runner` target

Template for a flavor scheme:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1640"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <PreActions>
         <ExecutionAction
            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent
               title = "Run Prepare Flutter Framework Script"
               scriptText = "/bin/sh &quot;$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh&quot; prepare&#10;">
               <EnvironmentBuildable>
                  <BuildableReference
                     BuildableIdentifier = "primary"
                     BlueprintIdentifier = "97C146ED1CF9000F007C117D"
                     BuildableName = "Runner.app"
                     BlueprintName = "Runner"
                     ReferencedContainer = "container:Runner.xcodeproj">
                  </BuildableReference>
               </EnvironmentBuildable>
            </ActionContent>
         </ExecutionAction>
      </PreActions>
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "97C146ED1CF9000F007C117D"
               BuildableName = "Runner.app"
               BlueprintName = "Runner"
               ReferencedContainer = "container:Runner.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug-{{FLAVOR}}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      customLLDBInitFile = "$(SRCROOT)/Flutter/ephemeral/flutter_lldbinit"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug-{{FLAVOR}}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      customLLDBInitFile = "$(SRCROOT)/Flutter/ephemeral/flutter_lldbinit"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "97C146ED1CF9000F007C117D"
            BuildableName = "Runner.app"
            BlueprintName = "Runner"
            ReferencedContainer = "container:Runner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release-{{FLAVOR}}"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "97C146ED1CF9000F007C117D"
            BuildableName = "Runner.app"
            BlueprintName = "Runner"
            ReferencedContainer = "container:Runner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug-{{FLAVOR}}">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release-{{FLAVOR}}"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

Replace `{{FLAVOR}}` with the actual flavor name.

### 3c. Create Export Options Plists

For each flavor, create `ios/export_options_{flavor}.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>{{EXPORT_METHOD}}</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>{{BUNDLE_ID}}</key>
        <string>match {{MATCH_TYPE}} {{BUNDLE_ID}}</string>
    </dict>
    <key>teamID</key>
    <string>{{APPLE_TEAM_ID}}</string>
</dict>
</plist>
```

Where:
- `{{EXPORT_METHOD}}`: `app-store` for prod/TestFlight, `ad-hoc` for dev/Firebase, `development` for local testing
- `{{BUNDLE_ID}}`: The full bundle ID for this flavor (base + suffix)
- `{{MATCH_TYPE}}`: `AppStore` for app-store method, `AdHoc` for ad-hoc, `Development` for development
- `{{APPLE_TEAM_ID}}`: The Apple Team ID

Ask the user which export method each flavor should use:
- **dev**: typically `ad-hoc` (for Firebase App Distribution) or `development`
- **staging**: typically `ad-hoc` (for Firebase App Distribution)
- **prod**: typically `app-store` (for TestFlight / App Store)

### 3d. Firebase per flavor (iOS)

If the user has separate Firebase configs per flavor:

1. Create flavor-specific directories or use build phase scripts:
   ```
   ios/config/dev/GoogleService-Info.plist
   ios/config/staging/GoogleService-Info.plist
   ios/config/prod/GoogleService-Info.plist
   ```
2. Add a Run Script build phase in Xcode (or document it) that copies the right `GoogleService-Info.plist` based on the build configuration:
   ```bash
   # Add to Runner target Build Phases → New Run Script Phase
   # Name: "Copy GoogleService-Info.plist for flavor"
   # Place BEFORE "Compile Sources"
   
   if [ "${CONFIGURATION}" == "Debug-dev" ] || [ "${CONFIGURATION}" == "Release-dev" ] || [ "${CONFIGURATION}" == "Profile-dev" ]; then
     cp "${PROJECT_DIR}/config/dev/GoogleService-Info.plist" "${PROJECT_DIR}/Runner/GoogleService-Info.plist"
   elif [ "${CONFIGURATION}" == "Debug-staging" ] || [ "${CONFIGURATION}" == "Release-staging" ] || [ "${CONFIGURATION}" == "Profile-staging" ]; then
     cp "${PROJECT_DIR}/config/staging/GoogleService-Info.plist" "${PROJECT_DIR}/Runner/GoogleService-Info.plist"
   elif [ "${CONFIGURATION}" == "Debug-prod" ] || [ "${CONFIGURATION}" == "Release-prod" ] || [ "${CONFIGURATION}" == "Profile-prod" ]; then
     cp "${PROJECT_DIR}/config/prod/GoogleService-Info.plist" "${PROJECT_DIR}/Runner/GoogleService-Info.plist"
   fi
   ```

---

## Step 4 — Dart/Flutter Flavor Configuration (Optional)

Ask: "Do you want to set up Dart-side flavor configuration?"

### Option A: Per-flavor entry points (recommended for complex setups)

Create separate `main` files per flavor:

**`lib/main_dev.dart`:**
```dart
import 'package:flutter/material.dart';
import 'app.dart';
import 'flavor_config.dart';

void main() {
  FlavorConfig.init(
    flavor: Flavor.dev,
    name: 'DEV',
    apiBaseUrl: 'https://api-dev.example.com',
  );
  runApp(const MyApp());
}
```

**`lib/main_prod.dart`:**
```dart
import 'package:flutter/material.dart';
import 'app.dart';
import 'flavor_config.dart';

void main() {
  FlavorConfig.init(
    flavor: Flavor.prod,
    name: 'PROD',
    apiBaseUrl: 'https://api.example.com',
  );
  runApp(const MyApp());
}
```

**`lib/flavor_config.dart`:**
```dart
enum Flavor { dev, staging, prod }

class FlavorConfig {
  static late Flavor flavor;
  static late String name;
  static late String apiBaseUrl;

  static void init({
    required Flavor flavor,
    required String name,
    required String apiBaseUrl,
  }) {
    FlavorConfig.flavor = flavor;
    FlavorConfig.name = name;
    FlavorConfig.apiBaseUrl = apiBaseUrl;
  }

  static bool get isDev => flavor == Flavor.dev;
  static bool get isProd => flavor == Flavor.prod;
}
```

With per-flavor entry points, the Flutter build command uses `--target`:
```bash
flutter build apk --flavor dev --target lib/main_dev.dart
flutter build apk --flavor prod --target lib/main_prod.dart
```

Update the Fastlane modules' build commands to include `--target` if entry points are used.

### Option B: Runtime flavor detection (simpler)

Use Flutter's built-in `appFlavor` constant:
```dart
import 'package:flutter/services.dart';

// In your app initialization:
final flavor = appFlavor; // Returns the --flavor value as a String
```

This requires no additional files but offers less compile-time configurability.

---

## Step 5 — Fastlane Environment Files

For each flavor, generate a `fastlane/env.{flavor}` file:

```
# =============================================================================
# Environment: {{FLAVOR}}
# Generated by /setup-flavors
# =============================================================================

# Build
FLAVOR={{FLAVOR}}
SCHEME={{FLAVOR}}
BUILD_FORMAT={{BUILD_FORMAT}}

# Firebase
FIREBASE_APP_ANDROID={{FIREBASE_APP_ANDROID}}
FIREBASE_APP_IOS={{FIREBASE_APP_IOS}}
APP_STORE_TESTER_GROUP={{TESTER_GROUP}}

# App Identity
APP_IDENTIFIER={{BUNDLE_ID_WITH_SUFFIX}}

# Apple
APPLE_TEAM_ID={{APPLE_TEAM_ID}}
APPLE_USERNAME={{APPLE_USERNAME}}

# AWS
AWS_PROFILE={{AWS_PROFILE}}
AWS_REGION={{AWS_REGION}}
MATCH_S3_BUCKET={{MATCH_S3_BUCKET}}
S3_KEYSTORE_BUCKET={{KEYSTORE_BUCKET}}
```

Key differences per flavor:
- `FLAVOR` and `SCHEME` match the flavor name
- `APP_IDENTIFIER` includes the bundle ID suffix for non-prod flavors
- `FIREBASE_APP_*` differs if using per-flavor Firebase apps
- `BUILD_FORMAT` may differ: `apk` for dev (Firebase), `aab` for prod (Play Store)
- `APP_STORE_TESTER_GROUP` may differ per flavor

If `env.secret` doesn't exist, create `fastlane/env.secret.example` with the required secrets.

---

## Step 6 — Confirmation & Execution

### 6a. Display summary

Show a complete summary of all changes that will be made:

```
=== Flavor Setup Summary ===

Flavors: dev, staging, prod
Base Bundle ID: com.company.myapp

Android changes:
  [MODIFY] android/app/build.gradle.kts — add productFlavors (dev, staging, prod)
  [MODIFY] android/app/src/main/AndroidManifest.xml — use @string/app_name
  [CREATE] android/app/src/dev/google-services.json
  [CREATE] android/app/src/prod/google-services.json

iOS changes:
  [CREATE] ios/Runner.xcodeproj/xcshareddata/xcschemes/staging.xcscheme
  [CREATE] ios/Runner.xcodeproj/xcshareddata/xcschemes/prod.xcscheme
  [CREATE] ios/export_options_staging.plist
  [CREATE] ios/export_options_prod.plist
  [SCRIPT] Ruby script to add build configurations to project.pbxproj
           (or manual Xcode steps)

Dart changes:
  [CREATE] lib/flavor_config.dart
  [CREATE] lib/main_dev.dart
  [CREATE] lib/main_prod.dart

Fastlane changes:
  [CREATE] fastlane/env.staging
  [CREATE] fastlane/env.prod
  [MODIFY] fastlane/env.dev (update values)
```

Ask: **"Does this look correct? Should I proceed? (y/N)"**

### 6b. Execute changes

Apply all changes in order:
1. Android `build.gradle.kts` modifications
2. Android `AndroidManifest.xml` updates
3. Android per-flavor directories (if Firebase per flavor)
4. iOS build configurations (via xcodeproj gem, Xcode instructions, or manual pbxproj edit)
5. iOS schemes
6. iOS export options plists
7. iOS per-flavor Firebase configs (if applicable)
8. Dart flavor configuration files (if selected)
9. Fastlane env files

### 6c. Warn before overwriting

Before modifying any existing file, show the user what will change and ask for confirmation. NEVER silently overwrite.

---

## Step 7 — Verification & Next Steps

After all changes are applied, provide:

### Verification commands
```bash
# Verify Android flavors
cd android && ./gradlew app:tasks --group="build" | grep -i "assemble"
# Should show: assembleDevDebug, assembleStagingDebug, assembleProdRelease, etc.

# Test Flutter build per flavor
flutter build apk --flavor dev --debug
flutter build apk --flavor staging --debug
flutter build apk --flavor prod --release

# Test iOS build (no codesign for local verification)
flutter build ios --flavor dev --no-codesign
flutter build ios --flavor prod --no-codesign

# Test via Fastlane
bundle exec fastlane android build --env dev
bundle exec fastlane ios build --env prod
```

### Remaining manual steps checklist
```
Flavor setup complete!

Remaining steps:

  1. Firebase (if per-flavor):
     - Register each flavor's applicationId/bundleId in Firebase Console
     - Download google-services.json / GoogleService-Info.plist per flavor
     - Place them in the correct directories (see above)

  2. iOS build configurations (if not automated):
     - Open ios/Runner.xcodeproj in Xcode
     - Project → Info → Configurations
     - Duplicate Debug/Release/Profile for each new flavor
     - Set PRODUCT_BUNDLE_IDENTIFIER per configuration

  3. iOS certificates (Fastlane Match):
     - Sync certificates for each bundle ID:
       bundle exec fastlane ios sync_certs --env dev
       bundle exec fastlane ios sync_certs --env prod

  4. Verify builds work:
     flutter run --flavor dev
     flutter run --flavor prod
```

---

## Important Rules

- NEVER delete existing flavors without explicit confirmation.
- If a flavor already exists on one platform, skip that platform's setup for that flavor and inform the user.
- When modifying `project.pbxproj`, always create a backup first: `cp project.pbxproj project.pbxproj.backup`
- Prefer using the `xcodeproj` Ruby gem over manual pbxproj editing. If neither is available, provide Xcode manual steps.
- Always verify that the generated `applicationIdSuffix` doesn't conflict with existing app registrations.
- The `SCHEME` in Fastlane env files must match the Xcode scheme filename (without `.xcscheme` extension).
- For the prod flavor, typically NO suffix is applied to the bundle ID — it uses the base identifier.
- Warn the user that adding flavors to an existing app may require re-registering the app in Firebase, App Store Connect, and Google Play Console for each new bundle ID variant.
- If working in the IDP repo itself (not a target project), generate templates with `{{PLACEHOLDER}}` variables instead of hardcoded values.
