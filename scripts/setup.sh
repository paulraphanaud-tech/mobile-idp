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

read_secret() {
  local prompt="$1"
  local var_name="$2"
  local value=""

  echo -n "$prompt: "
  read -r value
  eval "$var_name='$value'"
}

cmd_populate_secrets() {
  local env="${1:-dev}"
  echo "Populating secrets for environment: $env"
  echo ""

  local region="${AWS_REGION:-eu-west-1}"

  # --- Fastlane App Config ---
  echo -e "${YELLOW}=== Fastlane App Configuration ===${NC}"
  echo "Secret path: dev/secret/fastlane"
  echo ""

  read_secret "FLAVOR (e.g. dev)" FLAVOR
  read_secret "SCHEME (e.g. dev)" SCHEME
  read_secret "FIREBASE_APP_ANDROID" FIREBASE_APP_ANDROID
  read_secret "FIREBASE_APP_IOS" FIREBASE_APP_IOS
  read_secret "APP_STORE_TESTER_GROUP" APP_STORE_TESTER_GROUP
  read_secret "AWS_REGION for Fastlane" FL_AWS_REGION

  aws secretsmanager put-secret-value \
    --secret-id "dev/secret/fastlane" \
    --secret-string "{\"FLAVOR\":\"$FLAVOR\",\"SCHEME\":\"$SCHEME\",\"FIREBASE_APP_ANDROID\":\"$FIREBASE_APP_ANDROID\",\"FIREBASE_APP_IOS\":\"$FIREBASE_APP_IOS\",\"APP_STORE_TESTER_GROUP\":\"$APP_STORE_TESTER_GROUP\",\"AWS_REGION\":\"$FL_AWS_REGION\"}" \
    --region "$region"

  echo -e "${GREEN}[OK] dev/secret/fastlane populated${NC}"
  echo ""

  # --- Fastlane Credentials ---
  echo -e "${YELLOW}=== Fastlane Credentials ===${NC}"
  echo "Secret path: secret/env/fastlane"
  echo ""

  read_secret "FIREBASE_CLI_TOKEN" FIREBASE_CLI_TOKEN
  read_secret "APP_STORE_CONNECT_KEY_ID" ASC_KEY_ID
  read_secret "APP_STORE_CONNECT_ISSUER_ID" ASC_ISSUER_ID
  echo "APP_STORE_CONNECT_KEY_CONTENT (paste the key, then press Enter):"
  read -r ASC_KEY_CONTENT

  aws secretsmanager put-secret-value \
    --secret-id "secret/env/fastlane" \
    --secret-string "{\"FIREBASE_CLI_TOKEN\":\"$FIREBASE_CLI_TOKEN\",\"APP_STORE_CONNECT_KEY_ID\":\"$ASC_KEY_ID\",\"APP_STORE_CONNECT_ISSUER_ID\":\"$ASC_ISSUER_ID\",\"APP_STORE_CONNECT_KEY_CONTENT\":\"$ASC_KEY_CONTENT\"}" \
    --region "$region"

  echo -e "${GREEN}[OK] secret/env/fastlane populated${NC}"
  echo ""

  # --- Android Signing ---
  echo -e "${YELLOW}=== Android Signing ===${NC}"
  echo "Secret path: prod/android/signing"
  echo ""

  read_secret "KEYSTORE_BASE64 (base64-encoded keystore)" KEYSTORE_BASE64
  read_secret "KEYSTORE_PASSWORD" KEYSTORE_PASSWORD
  read_secret "KEY_ALIAS" KEY_ALIAS
  read_secret "KEY_PASSWORD" KEY_PASSWORD

  aws secretsmanager put-secret-value \
    --secret-id "prod/android/signing" \
    --secret-string "{\"KEYSTORE_BASE64\":\"$KEYSTORE_BASE64\",\"KEYSTORE_PASSWORD\":\"$KEYSTORE_PASSWORD\",\"KEY_ALIAS\":\"$KEY_ALIAS\",\"KEY_PASSWORD\":\"$KEY_PASSWORD\"}" \
    --region "$region"

  echo -e "${GREEN}[OK] prod/android/signing populated${NC}"
  echo ""

  # --- Google Play (optional) ---
  echo -e "${YELLOW}=== Google Play Store (optional) ===${NC}"
  echo "Secret path: prod/android/play_store"
  echo -n "Do you want to configure Google Play Store deployment? (y/N): "
  read -r configure_play

  if [[ "$configure_play" =~ ^[Yy]$ ]]; then
    echo "Paste Google Play service account JSON (single line):"
    read -r PLAY_JSON

    aws secretsmanager put-secret-value \
      --secret-id "prod/android/play_store" \
      --secret-string "{\"GOOGLE_PLAY_JSON_KEY_DATA\":$PLAY_JSON}" \
      --region "$region"

    echo -e "${GREEN}[OK] prod/android/play_store populated${NC}"
  else
    echo -e "${YELLOW}[SKIP] Google Play Store configuration skipped${NC}"
  fi

  echo ""
  echo -e "${GREEN}All secrets populated successfully!${NC}"
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
