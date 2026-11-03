# Native iOS (Xcode / SwiftUI) projects

The IDP started Flutter-only. Native iOS apps (a plain `.xcodeproj` /
`.xcworkspace`, SwiftUI or UIKit) are now supported with the same signing,
versioning and blast-radius rules, and with GitHub Actions as the CI.

## What is shared and what is not

| Piece | Flutter | Native iOS |
|---|---|---|
| Build | `modules/fastlane/ios_build` (`flutter build`, `ios/Runner.xcworkspace`) | `modules/fastlane/ios_native` (`scan` / `gym` on your project) |
| Signing | `match_s3`, readonly in CI | same |
| Versioning | `common.compute_next_version`, version written to the project | same computation, passed as `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` build settings — works with `GENERATE_INFOPLIST_FILE` projects, where `increment_version_number` edits nothing |
| App record | `produce` (`make create-app`, gated) | same |
| CI | CodeBuild + CodePipeline (Mac fleet) | GitHub Actions on GitHub-hosted macOS runners (`docs/github-actions.md`) |
| Secrets in CI | CodeBuild `SECRETS_MANAGER` env vars | GitHub OIDC → same Secrets Manager paths |
| Onboarding | `scripts/bootstrap.sh` (interactive) | `scripts/bootstrap-ios-native.sh` (non-interactive) |

## Onboarding

From the app repo root — no Mac needed, it only writes files:

```bash
bash /path/to/mobile-idp/scripts/bootstrap-ios-native.sh            # detect everything
bash /path/to/mobile-idp/scripts/bootstrap-ios-native.sh --help     # all flags
```

It detects the `.xcodeproj`, the first shared scheme, the app's
`PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM`, and writes:

| File | Purpose |
|---|---|
| `fastlane/Fastfile` | Lanes `test`, `build_simulator`, `build`, `deploy_testflight`, `sync_certs`, `create_app`, importing the IDP modules from `.idp/modules` |
| `fastlane/env.dev` | Non-secret config. Copy to `env.staging` / `env.prod` per environment. |
| `fastlane/env.secret.example` | Template for local-only secrets |
| `Gemfile`, `Makefile` | `make idp-fetch` clones the IDP into `.idp/` (gitignored) at the ref CI uses |
| `.idp.env` | What was detected; read by the workflow generator |
| `.github/workflows/*` | Via `scripts/generate-github-actions.sh` (`--workflows`, default `ci,preview`) |

The IDP is **not vendored** into the app: CI checks out mobile-idp at
`IDP_REF` (default `main`) into `.idp/`. Pin a tag for reproducibility.

The scheme must be **shared** (Xcode → Manage Schemes → Shared) or `xcodebuild`
on CI cannot see it. If its Test action has no test targets, generate CI with
`--build-only`.

## Make targets (in the app)

| Target | Tier |
|---|---|
| `make test`, `make build-simulator`, `make build-ios`, `make sync-certs*` | 1 |
| `make deploy-ios-testflight` | 2 — build number consumed forever |
| `make create-app APP_NAME=…` | 3 — gated by `scripts/confirm.sh "create <bundle-id>"` |
