#!/usr/bin/env bash
#
# Publish feature flags from flags.yaml to the configured backend.
#
#   bash scripts/flags.sh plan    dev     # read-only; shows what would change
#   bash scripts/flags.sh publish dev     # writes to the backend
#   bash scripts/flags.sh audit             # flag debt report
#
# The repo is the source of truth. A publish overwrites whatever the backend
# console currently holds — including changes someone made there by hand. That
# is the point: flag state stays reviewable, attributable and revertable.
#
# BLAST RADIUS. `publish` changes the behaviour of the installed app for real
# users, within the CDN TTL, with no build in between. It is recoverable — the
# flag bucket is versioned and Remote Config keeps template history — but it is
# the fastest path to production there is. Publishing to prod therefore requires
# the confirmation phrase; dev and staging do not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=codegen.sh
source "$SCRIPT_DIR/codegen.sh"

ENV_NAME="${2:-${ENV:-dev}}"

# In CI these arrive as CodeBuild environment variables set by Terraform
# (see infra/main.tf). Locally they are read from terraform output below.
FLAGS_BACKEND="${FLAGS_BACKEND:-}"
FLAGS_BUCKET="${FLAGS_BUCKET:-}"
FLAGS_DISTRIBUTION_ID="${FLAGS_DISTRIBUTION_ID:-}"

BUILD_DIR="${BUILD_DIR:-build/flags}"

# Fills in whatever the environment did not already provide, by reading
# terraform output. Skipped entirely in CI, where the variables are already
# set, and silent when terraform is unavailable or the state is not
# initialised — those are normal on a developer machine that has not applied
# this environment.
load_terraform_outputs() {
  [ -n "$FLAGS_BACKEND" ] && return 0
  FLAGS_BACKEND="none"

  [ -d "$REPO_ROOT/infra" ] || return 0
  command -v terraform >/dev/null 2>&1 || return 0

  local json
  json="$(cd "$REPO_ROOT/infra" && terraform output -json 2>/dev/null)" || return 0
  [ -n "$json" ] || return 0

  local parsed
  if command -v jq >/dev/null 2>&1; then
    parsed="$(printf '%s' "$json" | jq -r '
      [ (.feature_flags_backend.value // "none"),
        (.flags_bucket_name.value // ""),
        (.flags_distribution_id.value // "") ] | @tsv' 2>/dev/null)" || return 0
  elif command -v python3 >/dev/null 2>&1; then
    parsed="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def v(k, default=""):
    got = d.get(k, {}).get("value")
    return default if got is None else str(got)
print("\t".join([v("feature_flags_backend", "none"), v("flags_bucket_name"), v("flags_distribution_id")]))
' 2>/dev/null)" || return 0
  else
    return 0
  fi

  [ -n "$parsed" ] || return 0
  IFS=$'\t' read -r FLAGS_BACKEND FLAGS_BUCKET FLAGS_DISTRIBUTION_ID <<< "$parsed"
  FLAGS_BACKEND="${FLAGS_BACKEND:-none}"
}

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

render() {
  local env="$1" backend="$2" out="$3"
  mkdir -p "$(dirname "$out")"
  idp_codegen flags render \
    --registry "$FLAGS_REGISTRY" \
    --env "$env" \
    --backend "$backend" \
    --out "$out" >/dev/null
}

# Fetches what the backend serves today, so plan can diff against it. Writes an
# empty file when nothing is published yet — the first publish is a diff
# against nothing, not an error.
fetch_current() {
  local backend="$1" env="$2" out="$3"
  : > "$out"

  case "$backend" in
    aws)
      [ -n "$FLAGS_BUCKET" ] || return 0
      aws s3 cp "s3://$FLAGS_BUCKET/$env/flags.json" "$out" >/dev/null 2>&1 || : > "$out"
      ;;
    firebase)
      command -v firebase >/dev/null 2>&1 || return 0
      firebase remoteconfig:get -o "$out" >/dev/null 2>&1 || : > "$out"
      ;;
  esac
}

# Remote Config returns the live template with server-side metadata (etag,
# version, update timestamps) that we never send. Comparing raw would report a
# diff on every run, so both sides are reduced to the fields we actually
# publish. Without jq the diff is shown raw, with a note.
normalize() {
  local file="$1" backend="$2"
  if [ "$backend" = "firebase" ] && command -v jq >/dev/null 2>&1 && [ -s "$file" ]; then
    jq -S '{conditions: (.conditions // []), parameters: (.parameters // {})}' "$file" 2>/dev/null || cat "$file"
  elif command -v jq >/dev/null 2>&1 && [ -s "$file" ]; then
    jq -S 'del(.published_at)' "$file" 2>/dev/null || cat "$file"
  else
    cat "$file"
  fi
}

# Prints the diff. Returns 0 when something would change, 1 when nothing would.
show_diff() {
  local env="$1" backend="$2" rendered="$3"
  local current="$BUILD_DIR/$env.current"

  fetch_current "$backend" "$env" "$current"

  local a="$BUILD_DIR/.a" b="$BUILD_DIR/.b"
  normalize "$current" "$backend" > "$a"
  normalize "$rendered" "$backend" > "$b"

  if [ ! -s "$a" ]; then
    echo "${YELLOW}Nothing published to $backend/$env yet — this would be the first.${NC}"
    echo
    cat "$rendered"
    return 0
  fi

  if diff -u "$a" "$b" > "$BUILD_DIR/$env.diff" 2>/dev/null; then
    echo "${GREEN}No change:${NC} $backend/$env already matches $FLAGS_REGISTRY."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "${YELLOW}note:${NC} jq is not installed, so this diff includes backend metadata that is not actually changing."
  fi
  echo "${YELLOW}Changes to publish to $backend/$env:${NC}"
  echo
  sed -e "s|^-|${RED}-|" -e "s|^+|${GREEN}+|" -e "s|$|${NC}|" "$BUILD_DIR/$env.diff"
  return 0
}

# -----------------------------------------------------------------------------
# Publishing
# -----------------------------------------------------------------------------

publish_aws() {
  local env="$1" rendered="$2"

  [ -n "$FLAGS_BUCKET" ] || die "FLAGS_BUCKET is not set. Run: make infra-output ENV=$env"
  command -v aws >/dev/null 2>&1 || die "aws CLI not on PATH"

  info "uploading to s3://$FLAGS_BUCKET/$env/flags.json"
  # No Cache-Control: the CloudFront cache policy governs edge TTL, and an
  # origin header here would silently override the value in Terraform.
  aws s3 cp "$rendered" "s3://$FLAGS_BUCKET/$env/flags.json" \
    --content-type application/json \
    --only-show-errors

  if [ -n "$FLAGS_DISTRIBUTION_ID" ]; then
    info "invalidating /$env/flags.json"
    aws cloudfront create-invalidation \
      --distribution-id "$FLAGS_DISTRIBUTION_ID" \
      --paths "/$env/flags.json" \
      --query 'Invalidation.Id' --output text
  else
    echo "${YELLOW}note:${NC} FLAGS_DISTRIBUTION_ID not set — skipped invalidation. Changes appear once the CDN TTL expires."
  fi
}

publish_firebase() {
  local env="$1" rendered="$2"

  command -v firebase >/dev/null 2>&1 || die "firebase CLI not on PATH (npm i -g firebase-tools)"

  # firebase deploy reads the path named in firebase.json under
  # remoteconfig.template, so the rendered file has to land there.
  local target="${REMOTECONFIG_TEMPLATE:-remoteconfig.template.json}"
  cp "$rendered" "$REPO_ROOT/$target"
  info "wrote $target"

  local args=(deploy --only remoteconfig --non-interactive)
  [ -n "${FIREBASE_CLI_TOKEN:-}" ] && args+=(--token "$FIREBASE_CLI_TOKEN")
  [ -n "${FIREBASE_PROJECT:-}" ] && args+=(--project "$FIREBASE_PROJECT")

  (cd "$REPO_ROOT" && firebase "${args[@]}")

  echo "${YELLOW}note:${NC} Remote Config is per Firebase project, not per environment."
  echo "      Publishing '$env' overwrote the whole template. If dev and prod share"
  echo "      one Firebase project, they share one set of flag values — use separate"
  echo "      Firebase projects, or the aws backend, to separate them."
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

cmd_plan() {
  local env="$1"
  [ "$FLAGS_BACKEND" != "none" ] || die "FLAGS_BACKEND is \"none\" — nothing to publish to. Set feature_flags_backend in infra/environments/$env/terraform.tfvars."

  idp_codegen flags validate --registry "$FLAGS_REGISTRY"

  local rendered="$BUILD_DIR/$env.rendered.json"
  render "$env" "$FLAGS_BACKEND" "$rendered"
  show_diff "$env" "$FLAGS_BACKEND" "$rendered" || true
}

cmd_publish() {
  local env="$1"
  [ "$FLAGS_BACKEND" != "none" ] || die "FLAGS_BACKEND is \"none\" — nothing to publish to. Set feature_flags_backend in infra/environments/$env/terraform.tfvars."

  idp_codegen flags validate --registry "$FLAGS_REGISTRY"

  local rendered="$BUILD_DIR/$env.rendered.json"
  render "$env" "$FLAGS_BACKEND" "$rendered"

  if ! show_diff "$env" "$FLAGS_BACKEND" "$rendered"; then
    exit 0
  fi

  # Only prod is gated. dev and staging are where flags are supposed to be
  # flipped freely; a prompt there would train people to type past it.
  if [ "$env" = "prod" ]; then
    echo
    bash "$SCRIPT_DIR/confirm.sh" "publish flags prod" \
      "About to publish the flag changes above to PRODUCTION." \
      "They take effect on installed apps within the CDN TTL, with no build" \
      "in between and no app store review." \
      "Recoverable: restore the previous S3 object version, or roll back the" \
      "Remote Config template — but users will have seen the change first."
  fi

  case "$FLAGS_BACKEND" in
    aws) publish_aws "$env" "$rendered" ;;
    firebase) publish_firebase "$env" "$rendered" ;;
    *) die "unknown FLAGS_BACKEND: $FLAGS_BACKEND" ;;
  esac

  echo "${GREEN}published${NC} $FLAGS_REGISTRY to $FLAGS_BACKEND/$env"
}

usage_flags() {
  cat <<'EOF'
usage: scripts/flags.sh <command> [env]

  plan    <env>   Read-only. Renders flags.yaml and diffs it against what the
                  backend currently serves.
  publish <env>   Publishes. Shows the same diff first; prod requires the
                  confirmation phrase.
  audit           Reports flags past their expiry date. Read-only.

Backend and targets come from FLAGS_BACKEND / FLAGS_BUCKET /
FLAGS_DISTRIBUTION_ID, which `make flags-publish` reads from terraform output.
EOF
}

mkdir -p "$BUILD_DIR"
load_terraform_outputs

case "${1:-}" in
  plan)    cmd_plan "$ENV_NAME" ;;
  publish) cmd_publish "$ENV_NAME" ;;
  audit)   idp_codegen flags audit --registry "$FLAGS_REGISTRY" ;;
  ""|-h|--help|help) usage_flags ;;
  *) usage_flags; die "unknown command: $1" ;;
esac
