#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# IDP Bootstrap Script
# Sets up a new Flutter project with the CI/CD platform
#
# Usage:
#   From your new Flutter project root:
#     bash /path/to/fastlane-ci-cd/scripts/bootstrap.sh
#   Or with the repo cloned:
#     bash ci-cd/scripts/bootstrap.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Resolve the IDP repo root (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$IDP_ROOT/templates"
PROJECT_DIR="$(pwd)"

# =============================================================================
# Helper functions
# =============================================================================

banner() {
  echo ""
  echo -e "${BLUE}${BOLD}========================================${NC}"
  echo -e "${BLUE}${BOLD}  IDP Bootstrap — Flutter CI/CD${NC}"
  echo -e "${BLUE}${BOLD}========================================${NC}"
  echo ""
}

ask() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"

  if [ -n "$default" ]; then
    echo -ne "${BOLD}$prompt${NC} [${default}]: "
  else
    echo -ne "${BOLD}$prompt${NC}: "
  fi
  read -r value
  value="${value:-$default}"

  if [ -z "$value" ]; then
    echo -e "${RED}This field is required.${NC}"
    ask "$prompt" "$var_name" "$default"
    return
  fi

  eval "$var_name='$value'"
}

ask_choice() {
  local prompt="$1"
  local var_name="$2"
  local options="$3"
  local default="${4:-}"

  echo -ne "${BOLD}$prompt${NC} ($options) [${default}]: "
  read -r value
  value="${value:-$default}"
  eval "$var_name='$value'"
}

replace_placeholders() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' \
      -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{IOS_BUNDLE_ID}}|$IOS_BUNDLE_ID|g" \
      -e "s|{{ANDROID_PACKAGE_NAME}}|$ANDROID_PACKAGE_NAME|g" \
      -e "s|{{APPLE_TEAM_ID}}|$APPLE_TEAM_ID|g" \
      -e "s|{{APPLE_USERNAME}}|$APPLE_USERNAME|g" \
      -e "s|{{AWS_REGION}}|$AWS_REGION|g" \
      -e "s|{{AWS_PROFILE}}|$AWS_PROFILE|g" \
      -e "s|{{GCP_PROJECT_ID}}|$GCP_PROJECT_ID|g" \
      -e "s|{{GCP_REGION}}|$GCP_REGION|g" \
      -e "s|{{REPOSITORY_URL}}|$REPOSITORY_URL|g" \
      -e "s|{{GITHUB_REPO}}|$GITHUB_REPO|g" \
      -e "s|{{FIREBASE_APP_ANDROID}}|$FIREBASE_APP_ANDROID|g" \
      -e "s|{{FIREBASE_APP_IOS}}|$FIREBASE_APP_IOS|g" \
      -e "s|{{MODULES_PATH}}|$MODULES_PATH|g" \
      "$file"
  else
    sed -i \
      -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{IOS_BUNDLE_ID}}|$IOS_BUNDLE_ID|g" \
      -e "s|{{ANDROID_PACKAGE_NAME}}|$ANDROID_PACKAGE_NAME|g" \
      -e "s|{{APPLE_TEAM_ID}}|$APPLE_TEAM_ID|g" \
      -e "s|{{APPLE_USERNAME}}|$APPLE_USERNAME|g" \
      -e "s|{{AWS_REGION}}|$AWS_REGION|g" \
      -e "s|{{AWS_PROFILE}}|$AWS_PROFILE|g" \
      -e "s|{{GCP_PROJECT_ID}}|$GCP_PROJECT_ID|g" \
      -e "s|{{GCP_REGION}}|$GCP_REGION|g" \
      -e "s|{{REPOSITORY_URL}}|$REPOSITORY_URL|g" \
      -e "s|{{GITHUB_REPO}}|$GITHUB_REPO|g" \
      -e "s|{{FIREBASE_APP_ANDROID}}|$FIREBASE_APP_ANDROID|g" \
      -e "s|{{FIREBASE_APP_IOS}}|$FIREBASE_APP_IOS|g" \
      -e "s|{{MODULES_PATH}}|$MODULES_PATH|g" \
      "$file"
  fi
}

# =============================================================================
# Pre-flight checks
# =============================================================================

preflight() {
  if [ ! -f "$TEMPLATES_DIR/fastlane/Fastfile" ]; then
    echo -e "${RED}Error: Templates not found at $TEMPLATES_DIR${NC}"
    echo "Make sure you run this script from the IDP repository."
    exit 1
  fi

  if [ ! -f "$PROJECT_DIR/pubspec.yaml" ]; then
    echo -e "${YELLOW}Warning: No pubspec.yaml found in $PROJECT_DIR${NC}"
    echo -n "This doesn't look like a Flutter project. Continue anyway? (y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
}

# =============================================================================
# Collect project information
# =============================================================================

collect_info() {
  echo -e "${YELLOW}=== Project Information ===${NC}"
  echo ""

  # Try to infer project name from directory
  local default_name
  default_name="$(basename "$PROJECT_DIR")"

  ask "Project name (kebab-case)" PROJECT_NAME "$default_name"
  ask "iOS Bundle ID (e.g. com.company.app)" IOS_BUNDLE_ID ""
  ask "Android package name (e.g. com.company.app)" ANDROID_PACKAGE_NAME "$IOS_BUNDLE_ID"

  echo ""
  echo -e "${YELLOW}=== Apple Configuration ===${NC}"
  echo ""

  ask "Apple Team ID" APPLE_TEAM_ID ""
  ask "Apple Developer email" APPLE_USERNAME ""

  echo ""
  echo -e "${YELLOW}=== AWS Configuration ===${NC}"
  echo ""

  ask "AWS Region" AWS_REGION "eu-west-1"
  ask "AWS CLI Profile" AWS_PROFILE "default"

  echo ""
  echo -e "${YELLOW}=== GCP / Firebase Configuration ===${NC}"
  echo ""

  ask "GCP Project ID" GCP_PROJECT_ID ""
  ask "GCP Region" GCP_REGION "europe-west1"
  ask "Firebase App ID (Android)" FIREBASE_APP_ANDROID "TO_BE_CONFIGURED"
  ask "Firebase App ID (iOS)" FIREBASE_APP_IOS "TO_BE_CONFIGURED"

  echo ""
  echo -e "${YELLOW}=== Repository ===${NC}"
  echo ""

  # Try to infer from git remote
  local default_repo_url=""
  local default_github_repo=""
  if git remote get-url origin &>/dev/null; then
    default_repo_url="$(git remote get-url origin)"
    default_github_repo="$(echo "$default_repo_url" | sed -E 's|.*github\.com[:/](.+)(\.git)?$|\1|' | sed 's/\.git$//')"
  fi

  ask "Repository URL" REPOSITORY_URL "$default_repo_url"
  ask "GitHub repo (owner/repo)" GITHUB_REPO "$default_github_repo"

  echo ""
  echo -e "${YELLOW}=== Module Integration ===${NC}"
  echo ""

  echo "How do you want to integrate the IDP modules?"
  echo "  1) Git submodule (recommended — stays up to date)"
  echo "  2) Copy modules into this project"
  echo ""
  ask_choice "Choice" INTEGRATION_MODE "1/2" "1"
}

# =============================================================================
# Integrate modules
# =============================================================================

integrate_modules() {
  if [ "$INTEGRATION_MODE" = "1" ]; then
    echo ""
    echo -e "${BLUE}Adding IDP as git submodule...${NC}"

    local idp_remote=""
    if git -C "$IDP_ROOT" remote get-url origin &>/dev/null; then
      idp_remote="$(git -C "$IDP_ROOT" remote get-url origin)"
    fi

    if [ -z "$idp_remote" ]; then
      ask "IDP repository URL (for submodule)" idp_remote ""
    fi

    if [ ! -d "$PROJECT_DIR/ci-cd" ]; then
      git submodule add "$idp_remote" ci-cd
      echo -e "${GREEN}[OK] Submodule added at ci-cd/${NC}"
    else
      echo -e "${YELLOW}[SKIP] ci-cd/ already exists${NC}"
    fi

    MODULES_PATH="ci-cd/modules"

  else
    echo ""
    echo -e "${BLUE}Copying modules...${NC}"

    mkdir -p "$PROJECT_DIR/modules"
    cp -r "$IDP_ROOT/modules/fastlane" "$PROJECT_DIR/modules/fastlane"
    cp -r "$IDP_ROOT/modules/terraform" "$PROJECT_DIR/modules/terraform"

    echo -e "${GREEN}[OK] Modules copied to modules/${NC}"

    MODULES_PATH="modules"
  fi
}

# =============================================================================
# Generate files from templates
# =============================================================================

generate_files() {
  echo ""
  echo -e "${BLUE}Generating project files...${NC}"
  echo ""

  # --- Fastlane ---
  mkdir -p "$PROJECT_DIR/fastlane"

  if [ ! -f "$PROJECT_DIR/fastlane/Fastfile" ]; then
    cp "$TEMPLATES_DIR/fastlane/Fastfile" "$PROJECT_DIR/fastlane/Fastfile"
    replace_placeholders "$PROJECT_DIR/fastlane/Fastfile"
    echo -e "${GREEN}[OK] fastlane/Fastfile${NC}"
  else
    echo -e "${YELLOW}[SKIP] fastlane/Fastfile already exists${NC}"
  fi

  if [ ! -f "$PROJECT_DIR/fastlane/Pluginfile" ]; then
    cp "$TEMPLATES_DIR/fastlane/Pluginfile" "$PROJECT_DIR/fastlane/Pluginfile"
    echo -e "${GREEN}[OK] fastlane/Pluginfile${NC}"
  else
    echo -e "${YELLOW}[SKIP] fastlane/Pluginfile already exists${NC}"
  fi

  if [ ! -f "$PROJECT_DIR/fastlane/Matchfile" ]; then
    cp "$TEMPLATES_DIR/fastlane/Matchfile" "$PROJECT_DIR/fastlane/Matchfile"
    replace_placeholders "$PROJECT_DIR/fastlane/Matchfile"
    echo -e "${GREEN}[OK] fastlane/Matchfile${NC}"
  else
    echo -e "${YELLOW}[SKIP] fastlane/Matchfile already exists${NC}"
  fi

  cp "$TEMPLATES_DIR/fastlane/env.dev" "$PROJECT_DIR/fastlane/env.dev"
  replace_placeholders "$PROJECT_DIR/fastlane/env.dev"
  echo -e "${GREEN}[OK] fastlane/env.dev${NC}"

  cp "$TEMPLATES_DIR/fastlane/env.secret.example" "$PROJECT_DIR/fastlane/env.secret.example"
  echo -e "${GREEN}[OK] fastlane/env.secret.example${NC}"

  # --- Gemfile ---
  if [ ! -f "$PROJECT_DIR/Gemfile" ]; then
    cp "$TEMPLATES_DIR/Gemfile" "$PROJECT_DIR/Gemfile"
    echo -e "${GREEN}[OK] Gemfile${NC}"
  else
    echo -e "${YELLOW}[SKIP] Gemfile already exists${NC}"
  fi

  # --- Buildspec ---
  cp "$TEMPLATES_DIR/buildspec.yaml" "$PROJECT_DIR/buildspec.yaml"
  replace_placeholders "$PROJECT_DIR/buildspec.yaml"
  echo -e "${GREEN}[OK] buildspec.yaml${NC}"

  cp "$TEMPLATES_DIR/buildspec_ios.yml" "$PROJECT_DIR/buildspec_ios.yml"
  replace_placeholders "$PROJECT_DIR/buildspec_ios.yml"
  echo -e "${GREEN}[OK] buildspec_ios.yml${NC}"

  # --- Makefile ---
  if [ ! -f "$PROJECT_DIR/Makefile" ]; then
    cp "$TEMPLATES_DIR/Makefile" "$PROJECT_DIR/Makefile"
    replace_placeholders "$PROJECT_DIR/Makefile"
    echo -e "${GREEN}[OK] Makefile${NC}"
  else
    echo -e "${YELLOW}[SKIP] Makefile already exists${NC}"
  fi

  # --- Terraform environments ---
  mkdir -p "$PROJECT_DIR/infra/environments/dev"
  mkdir -p "$PROJECT_DIR/infra/environments/staging"
  mkdir -p "$PROJECT_DIR/infra/environments/prod"

  cp "$TEMPLATES_DIR/infra/environments/dev/terraform.tfvars" "$PROJECT_DIR/infra/environments/dev/terraform.tfvars"
  replace_placeholders "$PROJECT_DIR/infra/environments/dev/terraform.tfvars"
  echo -e "${GREEN}[OK] infra/environments/dev/terraform.tfvars${NC}"

  cp "$TEMPLATES_DIR/infra/environments/dev/backend.tf" "$PROJECT_DIR/infra/environments/dev/backend.tf"
  replace_placeholders "$PROJECT_DIR/infra/environments/dev/backend.tf"
  echo -e "${GREEN}[OK] infra/environments/dev/backend.tf${NC}"

  # --- Terraform main files (symlink or copy from modules) ---
  local tf_source="$PROJECT_DIR/$MODULES_PATH/terraform"

  for tf_file in main.tf providers.tf variables.tf outputs.tf versions.tf; do
    if [ ! -f "$PROJECT_DIR/infra/$tf_file" ] && [ -f "$IDP_ROOT/infra/$tf_file" ]; then
      cp "$IDP_ROOT/infra/$tf_file" "$PROJECT_DIR/infra/$tf_file"
      echo -e "${GREEN}[OK] infra/$tf_file${NC}"
    fi
  done

  # Update terraform module source paths in main.tf
  if [ -f "$PROJECT_DIR/infra/main.tf" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|source *= *\"../modules/terraform/|source = \"../$MODULES_PATH/terraform/|g" "$PROJECT_DIR/infra/main.tf"
    else
      sed -i "s|source *= *\"../modules/terraform/|source = \"../$MODULES_PATH/terraform/|g" "$PROJECT_DIR/infra/main.tf"
    fi
    echo -e "${GREEN}[OK] infra/main.tf module paths updated${NC}"
  fi

  # --- Scripts ---
  mkdir -p "$PROJECT_DIR/scripts"

  if [ ! -f "$PROJECT_DIR/scripts/setup.sh" ]; then
    cp "$IDP_ROOT/scripts/setup.sh" "$PROJECT_DIR/scripts/setup.sh"
    chmod +x "$PROJECT_DIR/scripts/setup.sh"
    echo -e "${GREEN}[OK] scripts/setup.sh${NC}"
  else
    echo -e "${YELLOW}[SKIP] scripts/setup.sh already exists${NC}"
  fi

  if [ -f "$IDP_ROOT/scripts/generate-keystore.sh" ]; then
    cp "$IDP_ROOT/scripts/generate-keystore.sh" "$PROJECT_DIR/scripts/generate-keystore.sh"
    chmod +x "$PROJECT_DIR/scripts/generate-keystore.sh"
    echo -e "${GREEN}[OK] scripts/generate-keystore.sh${NC}"
  fi

  # --- .gitignore additions ---
  local gitignore="$PROJECT_DIR/.gitignore"
  local ci_entries=(
    "fastlane/env.secret"
    "fastlane/report.xml"
    "fastlane/README.md"
    "*.keystore"
  )

  if [ -f "$gitignore" ]; then
    for entry in "${ci_entries[@]}"; do
      if ! grep -qF "$entry" "$gitignore"; then
        echo "$entry" >> "$gitignore"
      fi
    done
    echo -e "${GREEN}[OK] .gitignore updated${NC}"
  fi
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo -e "${GREEN}${BOLD}  Bootstrap complete!${NC}"
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo ""
  echo -e "Project: ${BOLD}$PROJECT_NAME${NC}"
  echo -e "iOS:     ${BOLD}$IOS_BUNDLE_ID${NC}"
  echo -e "Android: ${BOLD}$ANDROID_PACKAGE_NAME${NC}"
  echo ""
  echo -e "${YELLOW}Generated files:${NC}"
  echo "  fastlane/Fastfile"
  echo "  fastlane/Matchfile"
  echo "  fastlane/Pluginfile"
  echo "  fastlane/env.dev"
  echo "  fastlane/env.secret.example"
  echo "  Gemfile"
  echo "  Makefile"
  echo "  buildspec.yaml"
  echo "  buildspec_ios.yml"
  echo "  infra/environments/dev/terraform.tfvars"
  echo "  infra/environments/dev/backend.tf"
  echo "  infra/*.tf"
  echo "  scripts/setup.sh"
  echo ""
  echo -e "${YELLOW}Next steps:${NC}"
  echo ""
  echo "  1. Install dependencies:"
  echo "     ${BOLD}make install${NC}"
  echo ""
  echo "  2. Create Terraform state backend (S3 bucket + DynamoDB table):"
  echo "     ${BOLD}aws s3 mb s3://${PROJECT_NAME}-terraform-state --region ${AWS_REGION}${NC}"
  echo "     ${BOLD}aws dynamodb create-table --table-name ${PROJECT_NAME}-terraform-lock \\${NC}"
  echo "       ${BOLD}--attribute-definitions AttributeName=LockID,AttributeType=S \\${NC}"
  echo "       ${BOLD}--key-schema AttributeName=LockID,KeyType=HASH \\${NC}"
  echo "       ${BOLD}--billing-mode PAY_PER_REQUEST --region ${AWS_REGION}${NC}"
  echo ""
  echo "  3. Provision infrastructure:"
  echo "     ${BOLD}make infra-init${NC}"
  echo "     ${BOLD}make infra-plan${NC}"
  echo "     ${BOLD}make infra-apply${NC}"
  echo ""
  echo "  4. Populate secrets in AWS Secrets Manager:"
  echo "     ${BOLD}make populate-secrets${NC}"
  echo ""
  echo "  5. Confirm the CodeStar connection in AWS Console"
  echo ""
  echo "  6. Copy env.secret.example to env.secret and fill in values (local dev only):"
  echo "     ${BOLD}cp fastlane/env.secret.example fastlane/env.secret${NC}"
  echo ""
  echo "  7. Test a build:"
  echo "     ${BOLD}make build-android${NC}"
  echo "     ${BOLD}make build-ios${NC}"
  echo ""
}

# =============================================================================
# Main
# =============================================================================

banner
preflight
collect_info
integrate_modules
generate_files
print_summary
