#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Generate Android Keystore
# Creates a release keystore, encodes it to base64, and optionally uploads to S3
# =============================================================================

KEYSTORE_PATH="${KEYSTORE_PATH:-./release-key.jks}"
KEY_ALIAS="${KEY_ALIAS:-release-key}"
VALIDITY="${VALIDITY:-10000}"

echo "Android Keystore Generator"
echo "========================="
echo ""

if [ -f "$KEYSTORE_PATH" ]; then
  echo "Keystore already exists at $KEYSTORE_PATH"
  echo -n "Overwrite? (y/N): "
  read -r overwrite
  if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo -n "Keystore password: "
read -rs KEYSTORE_PASSWORD
echo ""

echo -n "Key password (press Enter to use same as keystore): "
read -rs KEY_PASSWORD
echo ""
KEY_PASSWORD="${KEY_PASSWORD:-$KEYSTORE_PASSWORD}"

echo -n "CN (Common Name, e.g. 'My App'): "
read -r CN
echo -n "OU (Organizational Unit, e.g. 'Mobile'): "
read -r OU
echo -n "O (Organization, e.g. 'My Company'): "
read -r O
echo -n "L (City, e.g. 'Paris'): "
read -r L
echo -n "ST (State, e.g. 'IDF'): "
read -r ST
echo -n "C (Country code, e.g. 'FR'): "
read -r C

DNAME="CN=${CN:-Android Release}, OU=${OU:-Mobile}, O=${O:-Company}, L=${L:-Paris}, ST=${ST:-IDF}, C=${C:-FR}"

echo ""
echo "Generating keystore..."

keytool -genkeypair -v \
  -keystore "$KEYSTORE_PATH" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity "$VALIDITY" \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DNAME"

echo ""
echo "Keystore generated at: $KEYSTORE_PATH"

# Base64 encode
B64_PATH="${KEYSTORE_PATH%.jks}_b64.txt"
base64 -i "$KEYSTORE_PATH" -o "$B64_PATH"
echo "Base64 encoded at: $B64_PATH"

# Optional S3 upload
echo ""
echo -n "Upload keystore to S3? (y/N): "
read -r upload

if [[ "$upload" =~ ^[Yy]$ ]]; then
  echo -n "S3 bucket name: "
  read -r BUCKET
  echo -n "AWS region (default: eu-west-1): "
  read -r REGION
  REGION="${REGION:-eu-west-1}"

  aws s3 cp "$KEYSTORE_PATH" "s3://$BUCKET/keystore/release-key.jks" --region "$REGION"
  echo "Keystore uploaded to s3://$BUCKET/keystore/release-key.jks"
fi

echo ""
echo "Done! Remember to:"
echo "  1. Save your passwords securely (AWS Secrets Manager)"
echo "  2. Add $KEYSTORE_PATH to .gitignore"
echo "  3. Never commit the keystore to git"
