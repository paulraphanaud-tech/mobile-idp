#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# IDP Setup Script
# Checks prerequisites and populates AWS Secrets Manager
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Secret paths
#
# Single source of truth for where each secret lives. Keep this in sync with
# `secret_definitions` in infra/variables.tf and the `secrets_manager_variables`
# block in infra/main.tf — CodeBuild resolves these at build start, and a path
# that does not exist fails the build before any phase runs.
# =============================================================================

secret_path() {
  local kind="$1" env="$2"
  case "$kind" in
    fastlane_config) echo "${env}/fastlane/config" ;;
    fastlane_creds)  echo "${env}/fastlane/credentials" ;;
    android_signing) echo "${env}/android/signing" ;;
    play_store)      echo "${env}/android/play_store" ;;
    *) echo "unknown secret kind: $kind" >&2; return 1 ;;
  esac
}

# =============================================================================
# Prerequisites
# =============================================================================

check_command() {
  if command -v "$1" &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} $1 found: $(command -v "$1")"
  else
    echo -e "${RED}[MISSING]${NC} $1 is required but not installed."
    return 1
  fi
}

cmd_check_prerequisites() {
  echo "Checking prerequisites..."
  echo ""
  local missing=0

  check_command terraform || missing=1
  check_command aws       || missing=1
  # jq builds the secret JSON payloads. Shell string interpolation cannot do
  # it safely: an App Store Connect PEM or a Play service-account JSON
  # contains quotes, backslashes and newlines that silently corrupt a
  # hand-built JSON string.
  check_command jq        || missing=1
  check_command flutter   || missing=1
  check_command ruby      || missing=1
  check_command bundler   || missing=1
  check_command fastlane  || missing=1
  check_command keytool   || missing=1

  echo ""
  if [ "$missing" -eq 1 ]; then
    echo -e "${RED}Some prerequisites are missing. Please install them before continuing.${NC}"
    exit 1
  else
    echo -e "${GREEN}All prerequisites are installed!${NC}"
  fi
}

# =============================================================================
# Input helpers
# =============================================================================

# Reads into a named variable without eval — a value containing a quote used
# to break the assignment (and could inject shell).
read_secret() {
  local prompt="$1" var_name="$2" value=""
  echo -n "$prompt: "
  read -r value
  printf -v "$var_name" '%s' "$value"
}

# Same, but does not echo. Use for anything that is actually a credential:
# terminal scrollback and screen shares are the most common leak path for
# hand-typed secrets.
read_secret_hidden() {
  local prompt="$1" var_name="$2" value=""
  echo -n "$prompt (input hidden): "
  read -rs value
  echo ""
  printf -v "$var_name" '%s' "$value"
}

put_secret() {
  local secret_id="$1" payload="$2" region="$3"
  aws secretsmanager put-secret-value \
    --secret-id "$secret_id" \
    --secret-string "$payload" \
    --region "$region" >/dev/null
  echo -e "${GREEN}[OK] ${secret_id} populated${NC}"
  echo ""
}

# =============================================================================
# populate-secrets
# =============================================================================

cmd_populate_secrets() {
  local env="${1:-dev}"
  local region="${AWS_REGION:-eu-west-1}"

  command -v jq >/dev/null || {
    echo -e "${RED}jq is required. Install it and re-run.${NC}"; exit 1; }

  echo "Populating secrets for environment: $env (region: $region)"
  echo ""

  # --- Fastlane app config (not credentials) ---
  local p_config; p_config="$(secret_path fastlane_config "$env")"
  echo -e "${YELLOW}=== Fastlane App Configuration ===${NC}"
  echo "Secret path: $p_config"
  echo ""

  read_secret "FLAVOR (e.g. $env)" FLAVOR
  read_secret "SCHEME (e.g. $env)" SCHEME
  read_secret "FIREBASE_APP_ANDROID" FIREBASE_APP_ANDROID
  read_secret "FIREBASE_APP_IOS" FIREBASE_APP_IOS
  read_secret "APP_STORE_TESTER_GROUP (group alias, not display name)" APP_STORE_TESTER_GROUP
  read_secret "AWS_REGION for Fastlane" FL_AWS_REGION

  put_secret "$p_config" "$(jq -nc \
    --arg flavor "$FLAVOR" \
    --arg scheme "$SCHEME" \
    --arg fb_android "$FIREBASE_APP_ANDROID" \
    --arg fb_ios "$FIREBASE_APP_IOS" \
    --arg tester_group "$APP_STORE_TESTER_GROUP" \
    --arg region "$FL_AWS_REGION" \
    '{FLAVOR:$flavor, SCHEME:$scheme, FIREBASE_APP_ANDROID:$fb_android,
      FIREBASE_APP_IOS:$fb_ios, APP_STORE_TESTER_GROUP:$tester_group,
      AWS_REGION:$region}')" "$region"

  # --- Fastlane credentials ---
  local p_creds; p_creds="$(secret_path fastlane_creds "$env")"
  echo -e "${YELLOW}=== Fastlane Credentials ===${NC}"
  echo "Secret path: $p_creds"
  echo ""

  read_secret_hidden "FIREBASE_CLI_TOKEN" FIREBASE_CLI_TOKEN
  read_secret "APP_STORE_CONNECT_KEY_ID" ASC_KEY_ID
  read_secret "APP_STORE_CONNECT_ISSUER_ID" ASC_ISSUER_ID
  echo "APP_STORE_CONNECT_KEY_CONTENT — paste the .p8 contents as a single"
  echo "line with literal \\n between the PEM lines:"
  read_secret_hidden "  key content" ASC_KEY_CONTENT
  # Required by infra/main.tf and buildspec_ios.yml. Omitting it makes the iOS
  # CodeBuild project fail at startup resolving the secret, before any phase
  # runs — which is why it is prompted for here rather than left to be set by
  # hand in the console.
  echo "MATCH_PASSWORD — the passphrase Match uses to encrypt certificates in"
  echo "S3. Must match what was used to create the Match repo."
  read_secret_hidden "  match password" MATCH_PASSWORD

  put_secret "$p_creds" "$(jq -nc \
    --arg fb_token "$FIREBASE_CLI_TOKEN" \
    --arg key_id "$ASC_KEY_ID" \
    --arg issuer_id "$ASC_ISSUER_ID" \
    --arg key_content "$ASC_KEY_CONTENT" \
    --arg match_password "$MATCH_PASSWORD" \
    '{FIREBASE_CLI_TOKEN:$fb_token, APP_STORE_CONNECT_KEY_ID:$key_id,
      APP_STORE_CONNECT_ISSUER_ID:$issuer_id,
      APP_STORE_CONNECT_KEY_CONTENT:$key_content,
      MATCH_PASSWORD:$match_password}')" "$region"

  # --- Android signing ---
  local p_signing; p_signing="$(secret_path android_signing "$env")"
  echo -e "${YELLOW}=== Android Signing ===${NC}"
  echo "Secret path: $p_signing"
  echo ""

  read_secret_hidden "KEYSTORE_BASE64 (base64-encoded keystore)" KEYSTORE_BASE64
  read_secret_hidden "KEYSTORE_PASSWORD" KEYSTORE_PASSWORD
  read_secret "KEY_ALIAS" KEY_ALIAS
  read_secret_hidden "KEY_PASSWORD" KEY_PASSWORD

  put_secret "$p_signing" "$(jq -nc \
    --arg b64 "$KEYSTORE_BASE64" \
    --arg store_pw "$KEYSTORE_PASSWORD" \
    --arg alias "$KEY_ALIAS" \
    --arg key_pw "$KEY_PASSWORD" \
    '{KEYSTORE_BASE64:$b64, KEYSTORE_PASSWORD:$store_pw,
      KEY_ALIAS:$alias, KEY_PASSWORD:$key_pw}')" "$region"

  # --- Google Play (optional) ---
  local p_play; p_play="$(secret_path play_store "$env")"
  echo -e "${YELLOW}=== Google Play Store (optional) ===${NC}"
  echo "Secret path: $p_play"
  echo -n "Configure Google Play Store deployment? (y/N): "
  read -r configure_play

  if [[ "$configure_play" =~ ^[Yy]$ ]]; then
    echo -n "Path to the Google Play service account JSON file: "
    read -r PLAY_JSON_PATH
    if [ ! -f "$PLAY_JSON_PATH" ]; then
      echo -e "${RED}No such file: $PLAY_JSON_PATH — skipping Play Store.${NC}"
    else
      # Read from a file rather than a paste: the JSON is multi-line and
      # contains an embedded PEM, which does not survive a single `read -r`.
      put_secret "$p_play" "$(jq -c '{GOOGLE_PLAY_JSON_KEY_DATA: .}' \
        "$PLAY_JSON_PATH")" "$region"
    fi
  else
    echo -e "${YELLOW}[SKIP] Google Play Store configuration skipped${NC}"
  fi

  echo ""
  echo -e "${GREEN}All secrets populated.${NC}"
}

# =============================================================================
# Main
# =============================================================================
case "${1:-check}" in
  check)
    cmd_check_prerequisites
    ;;
  populate-secrets)
    cmd_populate_secrets "${2:-dev}"
    ;;
  *)
    echo "Usage: $0 {check|populate-secrets [env]}"
    exit 1
    ;;
esac
