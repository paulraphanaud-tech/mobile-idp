#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Generate GitHub Actions workflows for a project onboarded on the IDP.
#
# Deterministic: same inputs, same YAML. The `generate-github-actions` skill
# collects the options and calls this; humans can call it directly.
#
# Usage (from the app repo root):
#   bash /path/to/mobile-idp/scripts/generate-github-actions.sh [options]
#
# Options:
#   --type ios-native|flutter   default: detected (pubspec.yaml → flutter, *.xcodeproj → ios-native)
#   --workflows LIST            comma-separated.
#                               ios-native: ci, preview, distribute (TestFlight or
#                                 Firebase; `testflight` is an alias), signing
#                               flutter: ci, preview (Android APK), ios-preview
#                                 (simulator), distribute (Android → Firebase,
#                                 iOS → TestFlight or Firebase), signing
#                               Default: ci,preview (ios-native); flutter: ci plus
#                               ios-preview if ios/ exists, preview if android/ exists
#                               or neither does. distribute/signing are opt-in.
#   --app-dir DIR               flutter: app directory relative to the repo root;
#                               default: . if ./pubspec.yaml, else the only app pubspec
#   --org ORG                   flutter: reverse-domain org for `flutter create` when
#                               a platform folder is missing; default: ORG from
#                               .idp.env, else com.example
#   --signing-key-id ID         flutter distribute/signing: which Android key in the
#                               signing repo; default: SIGNING_KEY_ID or PROJECT_NAME
#                               from .idp.env, else the repo directory name
#   --scheme NAME               default: SCHEME from .idp.env
#   --xcodeproj PATH            default: XCODE_PROJECT from .idp.env
#   --workspace PATH            default: XCODE_WORKSPACE from .idp.env
#   --runner LABEL              macOS runner label; default: macos-latest
#   --xcode VERSION             setup-xcode version; default: latest-stable
#   --timeout MINUTES           CI/preview job timeout; default: 30
#   --default-branch NAME       branch that triggers previews; default: main
#   --build-only                CI runs `build` instead of `test` (scheme has no test action)
#   --out DIR                   default: .github/workflows
#   --force                     overwrite existing workflow files
#   --dry-run                   print the rendered files instead of writing
#
# Writes only under --out and .github/dependabot.yml. No network, no secrets.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$IDP_ROOT/templates/github"

# Action versions in one place; dependabot keeps generated files current after.
# All Node 24 majors: GitHub now forces Node 20 actions onto Node 24, and
# configure-aws-credentials v4/v5 can hang at OIDC role assumption under it.
CHECKOUT_VERSION="v6"
UPLOAD_ARTIFACT_VERSION="v6"
AWS_CREDENTIALS_VERSION="v6"

TYPE="" WORKFLOWS="" RUNNER="macos-latest" XCODE_VERSION="latest-stable" TIMEOUT="30" DEPLOY_TIMEOUT="45"
DEFAULT_BRANCH="main" APP_DIR="" ARG_ORG="" ARG_SIGNING_KEY_ID="" BUILD_ONLY=0 OUT=".github/workflows" FORCE=0 DRY_RUN=0
ARG_SCHEME="" ARG_PROJECT="" ARG_WORKSPACE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --type)           TYPE="$2"; shift 2 ;;
    --workflows)      WORKFLOWS="$2"; shift 2 ;;
    --scheme)         ARG_SCHEME="$2"; shift 2 ;;
    --xcodeproj)      ARG_PROJECT="$2"; shift 2 ;;
    --workspace)      ARG_WORKSPACE="$2"; shift 2 ;;
    --runner)         RUNNER="$2"; shift 2 ;;
    --xcode)          XCODE_VERSION="$2"; shift 2 ;;
    --timeout)        TIMEOUT="$2"; shift 2 ;;
    --default-branch) DEFAULT_BRANCH="$2"; shift 2 ;;
    --app-dir)        APP_DIR="$2"; shift 2 ;;
    --org)            ARG_ORG="$2"; shift 2 ;;
    --build-only)     BUILD_ONLY=1; shift ;;
    --out)            OUT="$2"; shift 2 ;;
    --force)          FORCE=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --signing-key-id) ARG_SIGNING_KEY_ID="$2"; shift 2 ;;
    -h|--help)        sed -n '3,45p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

log()  { echo "[generate-github-actions] $*"; }
fail() { echo "[generate-github-actions] ERROR: $*" >&2; exit 1; }

# Values recorded by bootstrap-ios-native.sh, if present.
SCHEME="" XCODE_PROJECT="" XCODE_WORKSPACE="" IDP_REPO="paulraphanaud-tech/mobile-idp" IDP_REF="main"
AWS_REGION="eu-west-1" GITHUB_REPO="OWNER/REPO" IDP_PROJECT_TYPE="" IDP_APP_DIR="" ORG="" PROJECT_NAME="" SIGNING_KEY_ID=""
if [ -f .idp.env ]; then
  # shellcheck disable=SC1091
  set -a; . ./.idp.env; set +a
fi
ORG="${ARG_ORG:-${ORG:-com.example}}"
APP_DIR="${APP_DIR:-${IDP_APP_DIR:-}}"
SIGNING_KEY_ID="${ARG_SIGNING_KEY_ID:-${SIGNING_KEY_ID:-${PROJECT_NAME:-$(basename "$(pwd)" | tr '[:upper:]_ ' '[:lower:]--')}}}"
SCHEME="${ARG_SCHEME:-$SCHEME}"
XCODE_PROJECT="${ARG_PROJECT:-$XCODE_PROJECT}"
XCODE_WORKSPACE="${ARG_WORKSPACE:-$XCODE_WORKSPACE}"

if [ -z "$TYPE" ]; then
  if [ -n "$IDP_PROJECT_TYPE" ]; then TYPE="$IDP_PROJECT_TYPE"
  elif [ -f pubspec.yaml ] || [ -n "$APP_DIR" ]; then TYPE="flutter"
  elif ls ./*.xcodeproj >/dev/null 2>&1; then TYPE="ios-native"
  elif [ -n "$(find . -maxdepth 3 -name pubspec.yaml -not -path './packages/*' -not -path '*/example/*' \
         -exec grep -lqE '^[[:space:]]+sdk:[[:space:]]*flutter' {} \; -print 2>/dev/null)" ]; then
    TYPE="flutter"   # Flutter app in a subdirectory (monorepo); --app-dir is detected below
  else fail "cannot detect project type; pass --type"; fi
fi

case "$TYPE" in
  ios-native)
    WORKFLOWS="${WORKFLOWS:-ci,preview}"
    if [ -z "$XCODE_PROJECT" ] && [ -z "$XCODE_WORKSPACE" ]; then
      XCODE_PROJECT="$(find . -maxdepth 2 -name '*.xcodeproj' -not -path '*/Pods/*' | sed 's|^\./||' | head -1)"
    fi
    [ -n "$XCODE_PROJECT$XCODE_WORKSPACE" ] || fail "no Xcode project; pass --xcodeproj"
    [ -n "$SCHEME" ] || SCHEME="$(basename "${XCODE_PROJECT:-$XCODE_WORKSPACE}" | sed 's/\.xc\(odeproj\|workspace\)$//')"
    if [ -n "$XCODE_WORKSPACE" ]; then CONTAINER_FLAG="-workspace \"$XCODE_WORKSPACE\""
    else CONTAINER_FLAG="-project \"$XCODE_PROJECT\""; fi
    ;;
  flutter)
    if [ -z "$APP_DIR" ]; then
      if [ -f pubspec.yaml ]; then APP_DIR="."
      else
        # An app pubspec depends on the Flutter SDK and is not a package under
        # packages/ or a plugin's example/.
        mapfile -t cands < <(grep -lE '^[[:space:]]+sdk:[[:space:]]*flutter' \
          $(find . -maxdepth 3 -name pubspec.yaml -not -path './packages/*' \
              -not -path '*/example/*' -not -path './.dart_tool/*' | sort) 2>/dev/null || true)
        [ "${#cands[@]}" -eq 1 ] || fail "found ${#cands[@]} Flutter app pubspecs; pass --app-dir"
        APP_DIR="$(dirname "${cands[0]}" | sed 's|^\./||')"
      fi
    fi
    APP_DIR="${APP_DIR%/}"; APP_DIR="${APP_DIR#./}"; [ -n "$APP_DIR" ] || APP_DIR="."
    [ -f "$APP_DIR/pubspec.yaml" ] || fail "no pubspec.yaml in $APP_DIR"
    if [ -z "$WORKFLOWS" ]; then
      WORKFLOWS="ci"
      [ -d "$APP_DIR/ios" ] && WORKFLOWS="$WORKFLOWS,ios-preview"
      if [ -d "$APP_DIR/android" ] || [ ! -d "$APP_DIR/ios" ]; then WORKFLOWS="$WORKFLOWS,preview"; fi
    fi
    CONTAINER_FLAG=""
    ;;
  *) fail "unknown --type $TYPE" ;;
esac

if [ "$BUILD_ONLY" -eq 1 ]; then XCODEBUILD_ACTION="build"; ACTION_TITLE="Build"
else XCODEBUILD_ACTION="test"; ACTION_TITLE="Build & test"; fi

[ -n "$APP_DIR" ] || APP_DIR="."
if [ "$APP_DIR" = "." ]; then APP_PREFIX=""; else APP_PREFIX="$APP_DIR/"; fi

# Escape a value for the right-hand side of a sed s||| expression.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  local src="$1" dest="$2"
  [ -f "$src" ] || fail "template missing: $src"
  local content
  content="$(sed \
    -e "s|@@CHECKOUT_VERSION@@|$(esc "$CHECKOUT_VERSION")|g" \
    -e "s|@@UPLOAD_ARTIFACT_VERSION@@|$(esc "$UPLOAD_ARTIFACT_VERSION")|g" \
    -e "s|@@AWS_CREDENTIALS_VERSION@@|$(esc "$AWS_CREDENTIALS_VERSION")|g" \
    -e "s|@@RUNNER@@|$(esc "$RUNNER")|g" \
    -e "s|@@XCODE_VERSION@@|$(esc "$XCODE_VERSION")|g" \
    -e "s|@@TIMEOUT@@|$(esc "$TIMEOUT")|g" \
    -e "s|@@DEPLOY_TIMEOUT@@|$(esc "$DEPLOY_TIMEOUT")|g" \
    -e "s|@@DEFAULT_BRANCH@@|$(esc "$DEFAULT_BRANCH")|g" \
    -e "s|@@SCHEME@@|$(esc "$SCHEME")|g" \
    -e "s|@@CONTAINER_FLAG@@|$(esc "$CONTAINER_FLAG")|g" \
    -e "s|@@XCODEBUILD_ACTION@@|$(esc "$XCODEBUILD_ACTION")|g" \
    -e "s|@@ACTION_TITLE@@|$(esc "$ACTION_TITLE")|g" \
    -e "s|@@IDP_REPO@@|$(esc "$IDP_REPO")|g" \
    -e "s|@@IDP_REF@@|$(esc "$IDP_REF")|g" \
    -e "s|@@AWS_REGION@@|$(esc "$AWS_REGION")|g" \
    -e "s|@@GITHUB_REPO@@|$(esc "$GITHUB_REPO")|g" \
    -e "s|@@APP_DIR@@|$(esc "$APP_DIR")|g" \
    -e "s|@@APP_PREFIX@@|$(esc "$APP_PREFIX")|g" \
    -e "s|@@ORG@@|$(esc "$ORG")|g" \
    -e "s|@@SIGNING_KEY_ID@@|$(esc "$SIGNING_KEY_ID")|g" \
    "$src")"
  if printf '%s' "$content" | grep -q '@@[A-Z_]*@@'; then
    fail "unrendered placeholder in $dest: $(printf '%s' "$content" | grep -o '@@[A-Z_]*@@' | sort -u | tr '\n' ' ')"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "----- $dest -----"; printf '%s\n' "$content"; return
  fi
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    log "skip   $dest (exists; --force to overwrite)"; return
  fi
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" > "$dest"
  log "write  $dest"
}

IFS=',' read -r -a wanted <<< "$WORKFLOWS"
for wf in "${wanted[@]}"; do
  wf="$(echo "$wf" | tr -d ' ')"
  case "$TYPE:$wf" in
    ios-native:ci)         render "$TPL/workflows/ios-native-ci.yml"         "$OUT/ios-ci.yml" ;;
    ios-native:preview)    render "$TPL/workflows/ios-native-preview.yml"    "$OUT/ios-preview.yml" ;;
    ios-native:distribute|ios-native:testflight)
                           render "$TPL/workflows/ios-native-distribute.yml" "$OUT/distribute.yml" ;;
    ios-native:signing)    render "$TPL/workflows/ios-native-signing-setup.yml" "$OUT/signing-setup.yml" ;;
    flutter:ci)            render "$TPL/workflows/flutter-ci.yml"            "$OUT/flutter-ci.yml" ;;
    flutter:preview)       render "$TPL/workflows/flutter-preview.yml"       "$OUT/flutter-preview.yml" ;;
    flutter:ios-preview)   render "$TPL/workflows/flutter-ios-preview.yml"   "$OUT/flutter-ios-preview.yml" ;;
    flutter:distribute)    render "$TPL/workflows/flutter-distribute.yml"    "$OUT/distribute.yml" ;;
    flutter:signing)       render "$TPL/workflows/flutter-signing-setup.yml" "$OUT/signing-setup.yml" ;;
    *) fail "workflow '$wf' is not available for type $TYPE" ;;
  esac
done
render "$TPL/dependabot.yml" ".github/dependabot.yml"

log "type=$TYPE workflows=$WORKFLOWS app_dir=$APP_DIR scheme=${SCHEME:-n/a} runner=$RUNNER xcode=$XCODE_VERSION"
