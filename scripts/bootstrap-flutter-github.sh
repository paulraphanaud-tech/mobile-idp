#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# IDP Bootstrap — Flutter app, test distribution from GitHub Actions
#
# The light-weight counterpart of scripts/bootstrap.sh (interactive, provisions
# the CodeBuild pipeline on AWS). This one needs no AWS account, no Mac and no
# terminal prompts, so an agent can run it in a cloud session on an app that
# was just written in a chat — even one with only lib/ and pubspec.yaml:
#
#   fastlane/{Fastfile,env.dev,Pluginfile,env.secret.example}, Gemfile
#   .idp.env                     what was detected, read by the generator
#   .github/workflows/*          ci, previews, distribute, signing-setup
#
# Usage (from the app repo root):
#   bash /path/to/mobile-idp/scripts/bootstrap-flutter-github.sh [options]
#
# Options (all optional — detected when omitted):
#   --app-dir DIR              Flutter app directory; default: . or the only app
#                              pubspec in the repo
#   --project-name NAME        default: pubspec `name`
#   --org ORG                  reverse-domain org; default: from the bundle ID,
#                              else com.example
#   --bundle-id ID             iOS bundle ID; default: Runner's
#                              PRODUCT_BUNDLE_IDENTIFIER, else <org>.<name>
#   --team-id ID               Apple Team ID; default: DEVELOPMENT_TEAM, else
#                              TEAMID_TBD (set before the first iOS build)
#   --firebase-android-app ID  Firebase Android app ID (1:123:android:abc)
#   --firebase-ios-app ID      Firebase iOS app ID (1:123:ios:abc)
#   --tester-groups LIST       Firebase tester group aliases; default: testers
#   --github-repo O/R          default: from `git remote get-url origin`
#   --idp-repo O/R             default: paulraphanaud-tech/mobile-idp
#   --idp-ref REF              mobile-idp branch/tag CI checks out; default: main
#   --workflows LIST           passed to the generator;
#                              default: ci,preview,ios-preview,distribute,signing
#   --no-workflows             skip scripts/generate-github-actions.sh
#   --force                    overwrite files that already exist
#   --dry-run                  print what would be written, write nothing
#
# A project already bootstrapped for CodeBuild keeps its own fastlane/ files
# (they are skipped, as any existing file is); the workflows still work with
# it, but its Fastfile needs the `setup_signing` lane — see
# docs/github-distribution.md. Writes only inside the repo; no network.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$IDP_ROOT/templates/flutter-github"

APP_DIR="" PROJECT_NAME="" ORG="" IOS_BUNDLE_ID="" APPLE_TEAM_ID=""
FIREBASE_APP_ANDROID="" FIREBASE_APP_IOS="" FIREBASE_TESTER_GROUPS="testers"
GITHUB_REPO="" IDP_REPO="paulraphanaud-tech/mobile-idp" IDP_REF="main"
WORKFLOWS="ci,preview,ios-preview,distribute,signing" WITH_WORKFLOWS=1 FORCE=0 DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --app-dir)              APP_DIR="$2"; shift 2 ;;
    --project-name)         PROJECT_NAME="$2"; shift 2 ;;
    --org)                  ORG="$2"; shift 2 ;;
    --bundle-id)            IOS_BUNDLE_ID="$2"; shift 2 ;;
    --team-id)              APPLE_TEAM_ID="$2"; shift 2 ;;
    --firebase-android-app) FIREBASE_APP_ANDROID="$2"; shift 2 ;;
    --firebase-ios-app)     FIREBASE_APP_IOS="$2"; shift 2 ;;
    --tester-groups)        FIREBASE_TESTER_GROUPS="$2"; shift 2 ;;
    --github-repo)          GITHUB_REPO="$2"; shift 2 ;;
    --idp-repo)             IDP_REPO="$2"; shift 2 ;;
    --idp-ref)              IDP_REF="$2"; shift 2 ;;
    --workflows)            WORKFLOWS="$2"; shift 2 ;;
    --no-workflows)         WITH_WORKFLOWS=0; shift ;;
    --force)                FORCE=1; shift ;;
    --dry-run)              DRY_RUN=1; shift ;;
    -h|--help)              sed -n '3,45p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

log()  { echo "[bootstrap-flutter-github] $*"; }
fail() { echo "[bootstrap-flutter-github] ERROR: $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------
if [ -z "$APP_DIR" ]; then
  if [ -f pubspec.yaml ]; then APP_DIR="."
  else
    mapfile -t cands < <(find . -maxdepth 3 -name pubspec.yaml -not -path './packages/*' \
        -not -path '*/example/*' -not -path '*/.dart_tool/*' -not -path '*/.idp/*' 2>/dev/null \
      | sort | while read -r f; do grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter' "$f" && echo "$f"; done)
    [ "${#cands[@]}" -eq 1 ] || fail "found ${#cands[@]} Flutter app pubspecs; pass --app-dir"
    APP_DIR="$(dirname "${cands[0]}")"
  fi
fi
APP_DIR="${APP_DIR%/}"; APP_DIR="${APP_DIR#./}"; [ -n "$APP_DIR" ] || APP_DIR="."
[ -f "$APP_DIR/pubspec.yaml" ] || fail "no pubspec.yaml in $APP_DIR"
grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter' "$APP_DIR/pubspec.yaml" || fail "$APP_DIR/pubspec.yaml does not depend on Flutter"

PUB_NAME="$(sed -n 's/^name:[[:space:]]*\([A-Za-z0-9_]*\).*/\1/p' "$APP_DIR/pubspec.yaml" | head -1)"
[ -n "$PUB_NAME" ] || fail "no 'name:' in $APP_DIR/pubspec.yaml"
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="$(printf '%s' "$PUB_NAME" | tr '_' '-')"

PBXPROJ="$APP_DIR/ios/Runner.xcodeproj/project.pbxproj"
if [ -z "$IOS_BUNDLE_ID" ] && [ -f "$PBXPROJ" ]; then
  IOS_BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = "\{0,1\}\([^";$]*\)"\{0,1\};.*/\1/p' "$PBXPROJ" \
    | grep -viE 'tests?$' | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2- || true)"
fi
if [ -z "$ORG" ]; then
  if [ -n "$IOS_BUNDLE_ID" ] && [ "${IOS_BUNDLE_ID%.*}" != "$IOS_BUNDLE_ID" ]; then ORG="${IOS_BUNDLE_ID%.*}"
  else ORG="com.example"; fi
fi
# flutter create's own iOS default is <org>.<camelCase name>; any valid ID
# works, since fastlane sets it on the Release configuration at build time.
[ -n "$IOS_BUNDLE_ID" ] || IOS_BUNDLE_ID="$ORG.$(printf '%s' "$PUB_NAME" | tr -d '_')"

if [ -z "$APPLE_TEAM_ID" ] && [ -f "$PBXPROJ" ]; then
  APPLE_TEAM_ID="$(sed -n 's/.*DEVELOPMENT_TEAM = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' "$PBXPROJ" | head -1 || true)"
fi
[ -n "$APPLE_TEAM_ID" ] || APPLE_TEAM_ID="TEAMID_TBD"

GRADLE=""
for f in "$APP_DIR/android/app/build.gradle" "$APP_DIR/android/app/build.gradle.kts"; do [ -f "$f" ] && GRADLE="$f"; done
if [ -n "$GRADLE" ]; then
  ANDROID_PACKAGE="$(sed -n 's/.*applicationId[[:space:]=]*"\([^"]*\)".*/\1/p' "$GRADLE" | head -1)"
  ANDROID_PACKAGE_HINT="applicationId in ${GRADLE#"$APP_DIR"/}: ${ANDROID_PACKAGE:-see the file}"
else
  ANDROID_PACKAGE="$ORG.$PUB_NAME"
  ANDROID_PACKAGE_HINT="no android/ folder yet; CI generates one with package $ANDROID_PACKAGE"
fi

if [ -z "$GITHUB_REPO" ] && git remote get-url origin >/dev/null 2>&1; then
  GITHUB_REPO="$(git remote get-url origin | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|')"
fi
[ -n "$GITHUB_REPO" ] || GITHUB_REPO="OWNER/REPO"

if [ "$APP_DIR" = "." ]; then OUT="."; else OUT="$APP_DIR"; fi

log "app dir:         $APP_DIR (pubspec name: $PUB_NAME)"
log "iOS bundle id:   $IOS_BUNDLE_ID"
log "Android package: $ANDROID_PACKAGE"
log "team id:         $APPLE_TEAM_ID"
log "github repo:     $GITHUB_REPO"
log "IDP:             $IDP_REPO@$IDP_REF → $OUT/.idp/"
[ "$APPLE_TEAM_ID" = "TEAMID_TBD" ] && log "note: no Apple Team ID yet — set APPLE_TEAM_ID in fastlane/env.dev before the first iOS build."

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  local src="$1" dest="$OUT/$2"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    log "skip   $dest (exists; --force to overwrite)"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then log "would write $dest"; return; fi
  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|{{PROJECT_NAME}}|$(esc "$PROJECT_NAME")|g" \
    -e "s|{{IOS_BUNDLE_ID}}|$(esc "$IOS_BUNDLE_ID")|g" \
    -e "s|{{APPLE_TEAM_ID}}|$(esc "$APPLE_TEAM_ID")|g" \
    -e "s|{{FIREBASE_APP_ANDROID}}|$(esc "$FIREBASE_APP_ANDROID")|g" \
    -e "s|{{FIREBASE_APP_IOS}}|$(esc "$FIREBASE_APP_IOS")|g" \
    -e "s|{{FIREBASE_TESTER_GROUPS}}|$(esc "$FIREBASE_TESTER_GROUPS")|g" \
    -e "s|{{ANDROID_PACKAGE_HINT}}|$(esc "$ANDROID_PACKAGE_HINT")|g" \
    -e "s|{{IDP_REPO}}|$(esc "$IDP_REPO")|g" \
    -e "s|{{IDP_REF}}|$(esc "$IDP_REF")|g" \
    -e "s|{{MODULES_PATH}}|.idp/modules|g" \
    "$src" > "$dest"
  log "write  $dest"
}

render "$TEMPLATES_DIR/fastlane/Fastfile"           "fastlane/Fastfile"
render "$TEMPLATES_DIR/fastlane/env.dev"            "fastlane/env.dev"
render "$TEMPLATES_DIR/fastlane/env.secret.example" "fastlane/env.secret.example"
render "$TEMPLATES_DIR/fastlane/Pluginfile"         "fastlane/Pluginfile"
render "$TEMPLATES_DIR/Gemfile"                     "Gemfile"

if [ "$DRY_RUN" -ne 1 ]; then
  if [ -f "$OUT/fastlane/Fastfile" ] && ! grep -q 'lane :setup_signing' "$OUT/fastlane/Fastfile"; then
    log "note: the existing $OUT/fastlane/Fastfile has no 'setup_signing' lane — add it (docs/github-distribution.md) to use signing-setup.yml"
  fi

  cat > .idp.env <<EOF
# Written by mobile-idp scripts/bootstrap-flutter-github.sh — safe to edit, committed.
IDP_PROJECT_TYPE=flutter
IDP_REPO=$IDP_REPO
IDP_REF=$IDP_REF
IDP_APP_DIR=$APP_DIR
PROJECT_NAME=$PROJECT_NAME
ORG=$ORG
IOS_BUNDLE_ID=$IOS_BUNDLE_ID
ANDROID_PACKAGE=$ANDROID_PACKAGE
APPLE_TEAM_ID=$APPLE_TEAM_ID
SIGNING_KEY_ID=$ANDROID_PACKAGE
GITHUB_REPO=$GITHUB_REPO
EOF
  log "write  .idp.env"

  touch .gitignore
  for line in ".idp/" "fastlane/env.secret" "fastlane/report.xml" "fastlane/README.md" "*.mobileprovision" "*.p8"; do
    grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
  done
  log "update .gitignore"
fi

if [ "$WITH_WORKFLOWS" -eq 1 ]; then
  args=(--type flutter --app-dir "$APP_DIR" --org "$ORG" --signing-key-id "$ANDROID_PACKAGE" --workflows "$WORKFLOWS")
  [ "$FORCE" -eq 1 ] && args+=(--force)
  [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
  bash "$IDP_ROOT/scripts/generate-github-actions.sh" "${args[@]}"
fi

log "done. Next: commit and push; then docs/github-distribution.md — secrets, 'Signing setup', 'Distribute to testers'."
