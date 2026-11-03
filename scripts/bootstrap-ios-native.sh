#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# IDP Bootstrap — native iOS (Xcode / SwiftUI) project
#
# Renders templates/ios-native/ into an existing Xcode project and, by default,
# generates its GitHub Actions workflows. Unlike scripts/bootstrap.sh (Flutter,
# interactive), this one is non-interactive: every value is detected from the
# project or passed as a flag, so an agent can run it in a cloud session with
# no terminal and no Mac. It needs only bash, git, sed and find — no Xcode.
#
# Usage (from the app repo root):
#   bash /path/to/mobile-idp/scripts/bootstrap-ios-native.sh [options]
#
# Options (all optional — detected when omitted):
#   --project-name NAME     kebab-case; default: repo directory name
#   --xcodeproj PATH        default: the single *.xcodeproj at the repo root
#   --workspace PATH        .xcworkspace, if the project uses one
#   --scheme NAME           default: first shared scheme, else project name
#   --bundle-id ID          default: PRODUCT_BUNDLE_IDENTIFIER of the app target
#   --team-id ID            default: DEVELOPMENT_TEAM in the project, else TEAMID_TBD
#   --aws-region REGION     default: eu-west-1
#   --github-repo O/R       default: from `git remote get-url origin`
#   --idp-repo O/R          default: paulraphanaud-tech/mobile-idp
#   --idp-ref REF           branch or tag CI checks out; default: main
#   --no-workflows          skip scripts/generate-github-actions.sh
#   --workflows LIST        passed to the generator (default: ci,preview)
#   --force                 overwrite files that already exist
#   --dry-run               print what would be written, write nothing
#
# Never overwrites an existing file without --force. Touches nothing outside
# the current directory: no AWS, no Apple, no network.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$IDP_ROOT/templates/ios-native"
PROJECT_DIR="$(pwd)"

PROJECT_NAME="" XCODE_PROJECT="" XCODE_WORKSPACE="" SCHEME="" IOS_BUNDLE_ID="" APPLE_TEAM_ID=""
AWS_REGION="eu-west-1" GITHUB_REPO="" IDP_REPO="paulraphanaud-tech/mobile-idp" IDP_REF="main"
WITH_WORKFLOWS=1 WORKFLOWS="ci,preview" FORCE=0 DRY_RUN=0
MODULES_ROOT=".idp"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --xcodeproj)    XCODE_PROJECT="$2"; shift 2 ;;
    --workspace)    XCODE_WORKSPACE="$2"; shift 2 ;;
    --scheme)       SCHEME="$2"; shift 2 ;;
    --bundle-id)    IOS_BUNDLE_ID="$2"; shift 2 ;;
    --team-id)      APPLE_TEAM_ID="$2"; shift 2 ;;
    --aws-region)   AWS_REGION="$2"; shift 2 ;;
    --github-repo)  GITHUB_REPO="$2"; shift 2 ;;
    --idp-repo)     IDP_REPO="$2"; shift 2 ;;
    --idp-ref)      IDP_REF="$2"; shift 2 ;;
    --no-workflows) WITH_WORKFLOWS=0; shift ;;
    --workflows)    WORKFLOWS="$2"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      sed -n '3,35p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

MODULES_PATH="$MODULES_ROOT/modules"

log()  { echo "[bootstrap-ios-native] $*"; }
fail() { echo "[bootstrap-ios-native] ERROR: $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------
[ -f "$PROJECT_DIR/pubspec.yaml" ] && fail "pubspec.yaml found — this is a Flutter project; use scripts/bootstrap.sh"

if [ -z "$XCODE_PROJECT" ]; then
  mapfile -t projects < <(find . -maxdepth 2 -name '*.xcodeproj' -not -path '*/Pods/*' -not -path './.idp/*' | sed 's|^\./||' | sort)
  [ "${#projects[@]}" -eq 0 ] && fail "no .xcodeproj found; pass --xcodeproj"
  [ "${#projects[@]}" -gt 1 ] && fail "several .xcodeproj found (${projects[*]}); pass --xcodeproj"
  XCODE_PROJECT="${projects[0]}"
fi
[ -d "$XCODE_PROJECT" ] || fail "$XCODE_PROJECT does not exist"
PBXPROJ="$XCODE_PROJECT/project.pbxproj"
[ -f "$PBXPROJ" ] || fail "$PBXPROJ missing"

if [ -z "$SCHEME" ]; then
  SCHEME="$(find "$XCODE_PROJECT/xcshareddata/xcschemes" -name '*.xcscheme' 2>/dev/null | head -1 | xargs -I{} basename {} .xcscheme || true)"
  [ -z "$SCHEME" ] && SCHEME="$(basename "$XCODE_PROJECT" .xcodeproj)"
fi

# The app target's bundle ID: the shortest PRODUCT_BUNDLE_IDENTIFIER that is
# not a test bundle (test bundles are usually <app-id>.tests / Tests).
if [ -z "$IOS_BUNDLE_ID" ]; then
  IOS_BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = "\{0,1\}\([^";]*\)"\{0,1\};.*/\1/p' "$PBXPROJ" \
    | grep -viE 'tests?$|uitests' | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2- || true)"
  [ -z "$IOS_BUNDLE_ID" ] && fail "could not detect PRODUCT_BUNDLE_IDENTIFIER; pass --bundle-id"
fi

if [ -z "$APPLE_TEAM_ID" ]; then
  APPLE_TEAM_ID="$(sed -n 's/.*DEVELOPMENT_TEAM = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' "$PBXPROJ" | head -1 || true)"
  [ -z "$APPLE_TEAM_ID" ] && APPLE_TEAM_ID="TEAMID_TBD"
fi

if [ -z "$GITHUB_REPO" ] && git remote get-url origin >/dev/null 2>&1; then
  GITHUB_REPO="$(git remote get-url origin | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|')"
fi
[ -z "$GITHUB_REPO" ] && GITHUB_REPO="OWNER/REPO"

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR" | tr '[:upper:]_ ' '[:lower:]--')"
fi

log "project:     $PROJECT_NAME"
log "xcodeproj:   $XCODE_PROJECT ${XCODE_WORKSPACE:+(workspace $XCODE_WORKSPACE)}"
log "scheme:      $SCHEME"
log "bundle id:   $IOS_BUNDLE_ID"
log "team id:     $APPLE_TEAM_ID"
log "github repo: $GITHUB_REPO"
log "IDP:         $IDP_REPO@$IDP_REF → $MODULES_ROOT/"
[ "$APPLE_TEAM_ID" = "TEAMID_TBD" ] && log "note: no Apple Team ID yet — fine for CI tests and previews; set it before signed builds."

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------
# Escape a value for the right-hand side of a sed s||| expression.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  local src="$1" dest="$2"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    log "skip   $dest (exists; --force to overwrite)"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "would write $dest"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|{{PROJECT_NAME}}|$(esc "$PROJECT_NAME")|g" \
    -e "s|{{XCODE_PROJECT}}|$(esc "$XCODE_PROJECT")|g" \
    -e "s|{{XCODE_WORKSPACE}}|$(esc "$XCODE_WORKSPACE")|g" \
    -e "s|{{SCHEME}}|$(esc "$SCHEME")|g" \
    -e "s|{{IOS_BUNDLE_ID}}|$(esc "$IOS_BUNDLE_ID")|g" \
    -e "s|{{APPLE_TEAM_ID}}|$(esc "$APPLE_TEAM_ID")|g" \
    -e "s|{{AWS_REGION}}|$(esc "$AWS_REGION")|g" \
    -e "s|{{GITHUB_REPO}}|$(esc "$GITHUB_REPO")|g" \
    -e "s|{{IDP_REPO}}|$(esc "$IDP_REPO")|g" \
    -e "s|{{IDP_REF}}|$(esc "$IDP_REF")|g" \
    -e "s|{{MODULES_ROOT}}|$(esc "$MODULES_ROOT")|g" \
    -e "s|{{MODULES_PATH}}|$(esc "$MODULES_PATH")|g" \
    "$src" > "$dest"
  log "write  $dest"
}

render "$TEMPLATES_DIR/fastlane/Fastfile"           "fastlane/Fastfile"
render "$TEMPLATES_DIR/fastlane/env.dev"            "fastlane/env.dev"
render "$TEMPLATES_DIR/fastlane/env.secret.example" "fastlane/env.secret.example"
render "$TEMPLATES_DIR/Gemfile"                     "Gemfile"
render "$TEMPLATES_DIR/Makefile"                    "Makefile"

# Machine-readable record of what was detected; the workflow generator and the
# connect-app skill read it instead of re-detecting.
if [ "$DRY_RUN" -ne 1 ]; then
  cat > .idp.env <<EOF
# Written by mobile-idp scripts/bootstrap-ios-native.sh — safe to edit, committed.
IDP_PROJECT_TYPE=ios-native
IDP_REPO=$IDP_REPO
IDP_REF=$IDP_REF
PROJECT_NAME=$PROJECT_NAME
XCODE_PROJECT=$XCODE_PROJECT
XCODE_WORKSPACE=$XCODE_WORKSPACE
SCHEME=$SCHEME
IOS_BUNDLE_ID=$IOS_BUNDLE_ID
APPLE_TEAM_ID=$APPLE_TEAM_ID
AWS_REGION=$AWS_REGION
GITHUB_REPO=$GITHUB_REPO
EOF
  log "write  .idp.env"

  touch .gitignore
  for line in "$MODULES_ROOT/" "fastlane/env.secret" "fastlane/report.xml" "fastlane/README.md" "build/" "*.xcresult" "vendor/bundle/"; do
    grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
  done
  log "update .gitignore"
fi

if [ "$WITH_WORKFLOWS" -eq 1 ]; then
  args=(--type ios-native --workflows "$WORKFLOWS")
  [ "$FORCE" -eq 1 ] && args+=(--force)
  [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
  bash "$IDP_ROOT/scripts/generate-github-actions.sh" "${args[@]}"
fi

log "done. Next: commit, push, and watch the 'iOS CI' workflow on GitHub."
