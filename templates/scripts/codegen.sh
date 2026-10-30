#!/usr/bin/env bash
#
# Registry validation and code generation.
#
#   bash scripts/codegen.sh all                 # regenerate everything
#   bash scripts/codegen.sh flags codegen
#   bash scripts/codegen.sh events validate
#   bash scripts/codegen.sh tokens check        # CI: fail if out of date
#
# All read-only except "codegen"/"all", which write into lib/generated/.
# Nothing here touches a backend — see scripts/flags.sh for publishing.
#
# This file is also sourced by scripts/flags.sh for idp_codegen(); keep the
# sourcing guard at the bottom intact.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rendered by the IDP bootstrap: "ci-cd/modules" for a submodule integration,
# "modules" for a copied one.
MODULES_PATH="${MODULES_PATH:-{{MODULES_PATH}}}"
CODEGEN_DIR="$REPO_ROOT/$MODULES_PATH/flutter/idp_codegen"

FLAGS_REGISTRY="${FLAGS_REGISTRY:-flags/flags.yaml}"
EVENTS_REGISTRY="${EVENTS_REGISTRY:-analytics/events.yaml}"
TOKENS_FILE="${TOKENS_FILE:-design/tokens.json}"
GENERATED_DIR="${GENERATED_DIR:-lib/generated}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

die() { echo "${RED}error:${NC} $*" >&2; exit 1; }
info() { echo "${YELLOW}==>${NC} $*"; }

# Runs the generator. Resolves dependencies on first use only — `dart pub get`
# on every invocation would add a second or two to every build phase.
idp_codegen() {
  [ -d "$CODEGEN_DIR" ] || die "idp_codegen not found at $CODEGEN_DIR. Is the IDP submodule initialised? Try: git submodule update --init --recursive"
  command -v dart >/dev/null 2>&1 || die "dart not on PATH. Install the Flutter SDK."

  if [ ! -f "$CODEGEN_DIR/.dart_tool/package_config.json" ]; then
    info "resolving idp_codegen dependencies (first run)"
    (cd "$CODEGEN_DIR" && dart pub get >/dev/null)
  fi

  (cd "$REPO_ROOT" && dart run --no-serve-devtools "$CODEGEN_DIR/bin/idp_codegen.dart" "$@")
}

usage() {
  cat <<'EOF'
usage: scripts/codegen.sh <group> <action>

  all                      Regenerate flags, events and tokens
  check                    Verify every generated file is up to date (CI)

  flags   codegen|validate|check|audit
  events  codegen|validate|check
  tokens  codegen|validate|check

Environment overrides: FLAGS_REGISTRY, EVENTS_REGISTRY, TOKENS_FILE,
GENERATED_DIR, MODULES_PATH.
EOF
}

# A registry that does not exist is skipped rather than fatal: a project may
# legitimately use flags but not a design system, and failing a build over an
# absent optional file would force every project to adopt all three.
have() { [ -f "$REPO_ROOT/$1" ]; }

run_flags() {
  local action="$1"
  have "$FLAGS_REGISTRY" || { info "no $FLAGS_REGISTRY — skipping flags"; return 0; }
  case "$action" in
    codegen) idp_codegen flags codegen --registry "$FLAGS_REGISTRY" --out "$GENERATED_DIR/flags.g.dart" ;;
    check)   idp_codegen flags codegen --registry "$FLAGS_REGISTRY" --out "$GENERATED_DIR/flags.g.dart" --check ;;
    validate) idp_codegen flags validate --registry "$FLAGS_REGISTRY" ;;
    audit)   idp_codegen flags audit --registry "$FLAGS_REGISTRY" ;;
    *) die "unknown flags action: $action" ;;
  esac
}

run_events() {
  local action="$1"
  have "$EVENTS_REGISTRY" || { info "no $EVENTS_REGISTRY — skipping events"; return 0; }
  case "$action" in
    codegen) idp_codegen events codegen --registry "$EVENTS_REGISTRY" --out "$GENERATED_DIR/events.g.dart" ;;
    check)   idp_codegen events codegen --registry "$EVENTS_REGISTRY" --out "$GENERATED_DIR/events.g.dart" --check ;;
    validate) idp_codegen events validate --registry "$EVENTS_REGISTRY" ;;
    *) die "unknown events action: $action" ;;
  esac
}

run_tokens() {
  local action="$1"
  have "$TOKENS_FILE" || { info "no $TOKENS_FILE — skipping design tokens"; return 0; }
  case "$action" in
    codegen) idp_codegen tokens codegen --tokens "$TOKENS_FILE" --out "$GENERATED_DIR/design_tokens.g.dart" ;;
    check)   idp_codegen tokens codegen --tokens "$TOKENS_FILE" --out "$GENERATED_DIR/design_tokens.g.dart" --check ;;
    validate) idp_codegen tokens validate --tokens "$TOKENS_FILE" ;;
    *) die "unknown tokens action: $action" ;;
  esac
}

main() {
  case "${1:-}" in
    ""|-h|--help|help) usage; exit 0 ;;
    all)
      run_flags codegen && run_events codegen && run_tokens codegen
      echo "${GREEN}generated${NC} into $GENERATED_DIR/"
      ;;
    check)
      # Deliberately runs all three before failing, so one stale file does not
      # hide the other two.
      local status=0
      run_flags check  || status=1
      run_events check || status=1
      run_tokens check || status=1
      [ "$status" -eq 0 ] || die "generated code is out of date — run: make codegen"
      ;;
    validate)
      local status=0
      run_flags validate  || status=1
      run_events validate || status=1
      run_tokens validate || status=1
      exit "$status"
      ;;
    flags)  run_flags "${2:-validate}" ;;
    events) run_events "${2:-validate}" ;;
    tokens) run_tokens "${2:-validate}" ;;
    *) usage; die "unknown group: $1" ;;
  esac
}

# Sourced by scripts/flags.sh to reuse idp_codegen(); only run main when
# executed directly.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
