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
      -e "s|{{FEATURE_FLAGS_BACKEND}}|$FEATURE_FLAGS_BACKEND|g" \
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
      -e "s|{{FEATURE_FLAGS_BACKEND}}|$FEATURE_FLAGS_BACKEND|g" \
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
  echo -e "${YELLOW}=== Platform features ===${NC}"
  echo ""
  echo "Feature flags: where does the app read flag values from?"
  echo "  1) none     — defaults compiled in from flags.yaml only (add a backend later)"
  echo "  2) aws      — S3 + CloudFront document; targeting evaluated on device"
  echo "  3) firebase — Remote Config (note: per Firebase project, not per environment)"
  echo ""
  ask_choice "Choice" FLAGS_CHOICE "1/2/3" "1"

  case "$FLAGS_CHOICE" in
    2) FEATURE_FLAGS_BACKEND="aws" ;;
    3) FEATURE_FLAGS_BACKEND="firebase" ;;
    *) FEATURE_FLAGS_BACKEND="none" ;;
  esac

  echo ""
  echo -n -e "${BOLD}Include the Firebase Analytics sink? (Y/n)${NC}: "
  read -r reply
  if [[ "$reply" =~ ^[Nn]$ ]]; then
    INCLUDE_FIREBASE_ANALYTICS="false"
  else
    INCLUDE_FIREBASE_ANALYTICS="true"
  fi

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
    cp -r "$IDP_ROOT/modules/flutter" "$PROJECT_DIR/modules/flutter"

    # Resolved package metadata and build output from the IDP checkout are not
    # this project's, and a stale package_config.json makes the copied packages
    # fail to resolve here.
    find "$PROJECT_DIR/modules/flutter" \
      \( -name ".dart_tool" -o -name "build" -o -name ".packages" \) \
      -maxdepth 2 -exec rm -rf {} + 2>/dev/null || true

    echo -e "${GREEN}[OK] Modules copied to modules/${NC}"

    MODULES_PATH="modules"
  fi
}

# =============================================================================
# Generate files from templates
# =============================================================================

# Copies a template only when the destination does not exist, then substitutes
# placeholders. Used for files a team owns and edits — registries, the
# composition root — where clobbering is worse than being out of date.
generate_registry() {
  local dest="$1"
  local src="$2"

  mkdir -p "$PROJECT_DIR/$(dirname "$dest")"

  if [ -f "$PROJECT_DIR/$dest" ]; then
    echo -e "${YELLOW}[SKIP] $dest already exists${NC}"
    return 0
  fi

  cp "$src" "$PROJECT_DIR/$dest"
  replace_placeholders "$PROJECT_DIR/$dest"
  echo -e "${GREEN}[OK] $dest${NC}"
}

# Adds the IDP Flutter packages as path dependencies.
#
# Inserted directly after the "dependencies:" key rather than appended, because
# appending would land inside dev_dependencies or a trailing block. Skipped
# entirely if idp_analytics is already there, so re-running is safe.
wire_pubspec() {
  local pubspec="$PROJECT_DIR/pubspec.yaml"

  if [ ! -f "$pubspec" ]; then
    echo -e "${YELLOW}[SKIP] no pubspec.yaml — add the IDP packages manually${NC}"
    return 0
  fi

  if grep -q "idp_analytics:" "$pubspec"; then
    echo -e "${YELLOW}[SKIP] pubspec.yaml already references the IDP packages${NC}"
    return 0
  fi

  if ! grep -qE "^dependencies:" "$pubspec"; then
    echo -e "${YELLOW}[SKIP] pubspec.yaml has no dependencies: block${NC}"
    return 0
  fi

  local deps_file
  deps_file="$(mktemp)"
  {
    echo "  # --- IDP platform packages (added by bootstrap) ---"
    echo "  idp_analytics:"
    echo "    path: $MODULES_PATH/flutter/idp_analytics"
    echo "  idp_analytics_flutter:"
    echo "    path: $MODULES_PATH/flutter/idp_analytics_flutter"
    if [ "$INCLUDE_FIREBASE_ANALYTICS" = "true" ]; then
      echo "  idp_analytics_firebase:"
      echo "    path: $MODULES_PATH/flutter/idp_analytics_firebase"
    fi
    echo "  idp_feature_flags:"
    echo "    path: $MODULES_PATH/flutter/idp_feature_flags"
    case "$FEATURE_FLAGS_BACKEND" in
      aws)
        echo "  idp_feature_flags_aws:"
        echo "    path: $MODULES_PATH/flutter/idp_feature_flags_aws"
        ;;
      firebase)
        echo "  idp_feature_flags_firebase:"
        echo "    path: $MODULES_PATH/flutter/idp_feature_flags_firebase"
        ;;
    esac
  } > "$deps_file"

  awk -v deps="$deps_file" '
    { print }
    /^dependencies:[[:space:]]*$/ && !done {
      while ((getline line < deps) > 0) print line
      close(deps)
      done = 1
    }
  ' "$pubspec" > "$pubspec.idp.tmp" && mv "$pubspec.idp.tmp" "$pubspec"

  rm -f "$deps_file"
  echo -e "${GREEN}[OK] pubspec.yaml — IDP packages added${NC}"
}

# The IDP packages live inside the project tree (as a submodule at ci-cd/ or
# copied to modules/), so `flutter analyze` would descend into them and report
# hundreds of errors about dependencies that are resolved in their own
# directories rather than this one.
wire_analysis_options() {
  local file="$PROJECT_DIR/analysis_options.yaml"
  local exclude_path="$MODULES_PATH"
  exclude_path="${exclude_path%%/*}"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - build/**
    # The IDP packages are analyzed in their own directories, not here.
    - $exclude_path/**
    #
    # lib/generated/ is deliberately NOT excluded. Those files carry
    # "ignore_for_file: type=lint", which silences style lints while leaving
    # real type errors visible. Excluding them would hide a registry change
    # that no longer compiles.
EOF
    echo -e "${GREEN}[OK] analysis_options.yaml${NC}"
    return 0
  fi

  if grep -q "$exclude_path/\*\*" "$file"; then
    echo -e "${YELLOW}[SKIP] analysis_options.yaml already excludes $exclude_path/${NC}"
    return 0
  fi

  echo -e "${YELLOW}[MANUAL] add \"$exclude_path/**\" to analyzer.exclude in analysis_options.yaml${NC}"
  echo -e "         otherwise \`flutter analyze\` descends into the IDP packages."
}

# Best-effort first generation, so lib/generated/ exists before the first build.
# A failure here is not fatal: the project may not have Dart on PATH yet, and
# `make codegen` does the same thing later.
run_initial_codegen() {
  if ! command -v dart >/dev/null 2>&1; then
    echo -e "${YELLOW}[SKIP] dart not on PATH — run 'make codegen' once Flutter is installed${NC}"
    return 0
  fi

  if (cd "$PROJECT_DIR" && bash scripts/codegen.sh all >/dev/null 2>&1); then
    echo -e "${GREEN}[OK] lib/generated/ (flags, events, design tokens)${NC}"
  else
    echo -e "${YELLOW}[WARN] initial codegen failed — run 'make codegen' and read the errors${NC}"
  fi
}

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

  # All three environments, not just dev: `make infra-init ENV=staging` reads
  # environments/staging/backend.tf, and a missing file is a confusing failure
  # three weeks after bootstrap rather than now.
  for env in dev staging prod; do
    for f in terraform.tfvars backend.tf; do
      cp "$TEMPLATES_DIR/infra/environments/$env/$f" "$PROJECT_DIR/infra/environments/$env/$f"
      replace_placeholders "$PROJECT_DIR/infra/environments/$env/$f"
      echo -e "${GREEN}[OK] infra/environments/$env/$f${NC}"
    done
  done

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

  # --- Registries (flags, analytics events, design tokens) ---
  #
  # Never overwritten. These are the files a team edits constantly, and a
  # re-run of bootstrap must not silently revert a month of flag definitions.
  generate_registry "flags/flags.yaml" "$TEMPLATES_DIR/flags/flags.yaml"
  generate_registry "analytics/events.yaml" "$TEMPLATES_DIR/analytics/events.yaml"
  generate_registry "design/tokens.json" "$TEMPLATES_DIR/design/tokens.json"

  # --- Composition root ---
  #
  # Also never overwritten: it is a starting point the project owns and edits,
  # not generated code.
  generate_registry "lib/idp.dart" "$TEMPLATES_DIR/lib/idp.dart"

  # --- Scripts ---
  mkdir -p "$PROJECT_DIR/scripts"

  if [ ! -f "$PROJECT_DIR/scripts/setup.sh" ]; then
    cp "$IDP_ROOT/scripts/setup.sh" "$PROJECT_DIR/scripts/setup.sh"
    chmod +x "$PROJECT_DIR/scripts/setup.sh"
    echo -e "${GREEN}[OK] scripts/setup.sh${NC}"
  else
    echo -e "${YELLOW}[SKIP] scripts/setup.sh already exists${NC}"
  fi

  # Called by both buildspecs; a generated project without it fails the build
  # at the install phase.
  for s in supply-chain.sh build-metrics.sh codegen.sh flags.sh; do
    cp "$TEMPLATES_DIR/scripts/$s" "$PROJECT_DIR/scripts/$s"
    # codegen.sh embeds {{MODULES_PATH}} so it can find idp_codegen.
    replace_placeholders "$PROJECT_DIR/scripts/$s"
    chmod +x "$PROJECT_DIR/scripts/$s"
    echo -e "${GREEN}[OK] scripts/$s${NC}"
  done

  if [ -f "$IDP_ROOT/scripts/confirm.sh" ]; then
    cp "$IDP_ROOT/scripts/confirm.sh" "$PROJECT_DIR/scripts/confirm.sh"
    chmod +x "$PROJECT_DIR/scripts/confirm.sh"
    echo -e "${GREEN}[OK] scripts/confirm.sh${NC}"
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
    "*.jks"
    # Saved terraform plans are not encrypted and can contain resolved
    # variable values — see `make infra-plan`.
    "*.tfplan"
    ".terraform/"
    "*.tfstate"
    "*.tfstate.*"
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
  echo -e ""
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo -e "${GREEN}${BOLD}  Bootstrap complete!${NC}"
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo -e ""
  echo -e "Project: ${BOLD}$PROJECT_NAME${NC}"
  echo -e "iOS:     ${BOLD}$IOS_BUNDLE_ID${NC}"
  echo -e "Android: ${BOLD}$ANDROID_PACKAGE_NAME${NC}"
  echo -e ""
  echo -e "${YELLOW}Generated files:${NC}"
  echo -e "  fastlane/Fastfile"
  echo -e "  fastlane/Matchfile"
  echo -e "  fastlane/Pluginfile"
  echo -e "  fastlane/env.dev"
  echo -e "  fastlane/env.secret.example"
  echo -e "  Gemfile"
  echo -e "  Makefile"
  echo -e "  buildspec.yaml"
  echo -e "  buildspec_ios.yml"
  echo -e "  infra/environments/{dev,staging,prod}/terraform.tfvars"
  echo -e "  infra/environments/{dev,staging,prod}/backend.tf"
  echo -e "  infra/*.tf"
  echo -e "  scripts/setup.sh"
  echo -e "  scripts/confirm.sh"
  echo -e "  scripts/supply-chain.sh"
  echo -e "  scripts/build-metrics.sh"
  echo -e "  scripts/codegen.sh"
  echo -e "  scripts/flags.sh"
  echo -e "  flags/flags.yaml"
  echo -e "  analytics/events.yaml"
  echo -e "  design/tokens.json"
  echo -e "  lib/idp.dart"
  echo -e "  lib/generated/{flags,events,design_tokens}.g.dart"
  echo -e ""
  echo -e "Feature flag backend: ${BOLD}$FEATURE_FLAGS_BACKEND${NC}"
  echo -e ""
  echo -e "${YELLOW}Next steps:${NC}"
  echo -e ""
  echo -e "  1. Install dependencies:"
  echo -e "     ${BOLD}make install${NC}"
  echo -e ""
  echo -e "  2. Create Terraform state backend (S3 bucket + DynamoDB table):"
  echo -e "     ${BOLD}aws s3 mb s3://${PROJECT_NAME}-terraform-state --region ${AWS_REGION}${NC}"
  echo -e "     ${BOLD}aws dynamodb create-table --table-name ${PROJECT_NAME}-terraform-lock \\${NC}"
  echo -e "       ${BOLD}--attribute-definitions AttributeName=LockID,AttributeType=S \\${NC}"
  echo -e "       ${BOLD}--key-schema AttributeName=LockID,KeyType=HASH \\${NC}"
  echo -e "       ${BOLD}--billing-mode PAY_PER_REQUEST --region ${AWS_REGION}${NC}"
  echo -e ""
  echo -e "  3. Provision infrastructure:"
  echo -e "     ${BOLD}make infra-init${NC}"
  echo -e "     ${BOLD}make infra-plan${NC}"
  echo -e "     ${BOLD}make infra-apply${NC}"
  echo -e ""
  echo -e "  4. Populate secrets in AWS Secrets Manager:"
  echo -e "     ${BOLD}make populate-secrets${NC}"
  echo -e ""
  echo -e "  5. Confirm the CodeStar connection in AWS Console"
  echo -e ""
  echo -e "  6. Copy env.secret.example to env.secret and fill in values (local dev only):"
  echo -e "     ${BOLD}cp fastlane/env.secret.example fastlane/env.secret${NC}"
  echo -e ""
  echo -e "  7. Test a build:"
  echo -e "     ${BOLD}make build-android${NC}"
  echo -e "     ${BOLD}make build-ios${NC}"
  echo -e ""
  echo -e "  8. Wire up the platform services:"
  echo -e "     - uncomment the backends you chose in ${BOLD}lib/idp.dart${NC}"
  echo -e "     - call ${BOLD}Idp.initialize(...)${NC} before runApp"
  echo -e "     - pass ${BOLD}AppTheme.light${NC} / ${BOLD}AppTheme.dark${NC} to MaterialApp"
  echo -e "     - ${BOLD}flutter pub get${NC}"
  echo -e ""
  echo -e "     Edit the registries, then ${BOLD}make codegen${NC} and commit the result:"
  echo -e "       flags/flags.yaml        feature flags"
  echo -e "       analytics/events.yaml   analytics events"
  echo -e "       design/tokens.json      colours, spacing, type scale"
  echo -e ""

  if [ "$FEATURE_FLAGS_BACKEND" = "aws" ]; then
    echo -e "  9. After infra-apply, put the flag document URL in fastlane/env.dev:"
    echo -e "     ${BOLD}make infra-output ENV=dev | grep flags_document_url${NC}"
    echo -e "     then ${BOLD}make flags-plan ENV=dev${NC} and ${BOLD}make flags-publish ENV=dev${NC}"
    echo -e ""
  elif [ "$FEATURE_FLAGS_BACKEND" = "firebase" ]; then
    echo -e "  9. Point firebase.json at the rendered template:"
    echo -e "     ${BOLD}\"remoteconfig\": { \"template\": \"remoteconfig.template.json\" }${NC}"
    echo -e "     then ${BOLD}make flags-plan ENV=dev${NC} and ${BOLD}make flags-publish ENV=dev${NC}"
    echo -e ""
  fi
}

# =============================================================================
# Main
# =============================================================================

banner
preflight
collect_info
integrate_modules
generate_files
wire_pubspec
wire_analysis_options
run_initial_codegen
print_summary
