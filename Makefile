# =============================================================================
# IDP Modulaire - Flutter CI/CD
# =============================================================================

ENV ?= dev
AWS_REGION ?= eu-west-1
BUMP ?= patch
TRACK ?= internal

# =============================================================================
# Infrastructure (Terraform)
#
# infra-apply and infra-destroy are gated by scripts/confirm.sh. See CLAUDE.md,
# "Blast radius and confirmation gates", for which targets are safe to repeat
# and which need a human. AI agents must never set CONFIRM or AUTO_APPROVE.
# =============================================================================
.PHONY: infra-init infra-plan infra-apply infra-destroy infra-output

# Name of the project actually described by this environment's tfvars, so the
# destroy phrase names the real target rather than a guess.
PROJECT_NAME ?= $(shell sed -n 's/^[[:space:]]*project_name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' infra/environments/$(ENV)/terraform.tfvars 2>/dev/null)
TARGET_NAME = $(if $(PROJECT_NAME),$(PROJECT_NAME),unknown-project)-$(ENV)

# Saved plan, relative to infra/. Applied verbatim so that what gets applied is
# exactly what was reviewed — not a re-plan that may have drifted since.
PLAN_FILE = .terraform-plan-$(ENV).tfplan

infra-init:
	cd infra && terraform init -backend-config=environments/$(ENV)/backend.tf

infra-plan:
	cd infra && terraform plan -var-file=environments/$(ENV)/terraform.tfvars -out=$(PLAN_FILE)

# Depends on infra-plan: the full plan is always printed, unpiped and
# untruncated, immediately above the confirmation prompt.
infra-apply: infra-plan
	@echo ""
	@echo "Review the full plan printed above before continuing."
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		echo "AUTO_APPROVE=1 — applying without review. Intended for pipelines only."; \
	else \
		bash scripts/confirm.sh "apply $(ENV)" \
			"About to apply the plan above to '$(TARGET_NAME)'." \
			"This creates or modifies real AWS and Firebase resources."; \
	fi
	cd infra && terraform apply $(PLAN_FILE)

infra-destroy:
	@bash scripts/confirm.sh "destroy $(TARGET_NAME)" \
		"DESTRUCTIVE: terraform destroy on environment '$(ENV)'." \
		"Deletes CodeBuild projects, the Mac fleet, CodePipeline, IAM roles," \
		"the CodeStar connection and the Secrets Manager entries for $(ENV)." \
		"S3 buckets have force_destroy=false, so destroy will FAIL while the" \
		"match / keystore buckets still hold objects — signing material is not" \
		"silently deleted, but everything else is."
	cd infra && terraform destroy -var-file=environments/$(ENV)/terraform.tfvars

infra-output:
	cd infra && terraform output

# =============================================================================
# Secrets (populate after infra-apply)
# =============================================================================
.PHONY: populate-secrets secrets-audit

populate-secrets:
	@bash scripts/setup.sh populate-secrets $(ENV)

# Read-only. Reports how old each secret is against its recommended rotation
# cadence, and flags secrets Terraform created but nobody ever populated —
# CodeBuild fails at startup on those, before any build phase runs.
secrets-audit:
	@bash scripts/setup.sh secrets-audit $(ENV)

# =============================================================================
# Flutter
# =============================================================================
.PHONY: flutter-clean flutter-get flutter-run flutter-test

flutter-clean:
	flutter clean && flutter pub get

flutter-get:
	flutter pub get

flutter-run:
	flutter run

flutter-test:
	flutter test

# =============================================================================
# Android - Fastlane
# =============================================================================
.PHONY: build-android deploy-android-firebase deploy-android-play-store

build-android:
	bundle exec fastlane android build bump:$(BUMP)

deploy-android-firebase:
	bundle exec fastlane android deploy_firebase bump:$(BUMP)

deploy-android-play-store:
	bundle exec fastlane android deploy_play_store bump:$(BUMP) track:$(TRACK)

# =============================================================================
# iOS - Fastlane
# =============================================================================
.PHONY: build-ios deploy-ios-firebase deploy-ios-testflight

build-ios:
	bundle exec fastlane ios build bump:$(BUMP)

deploy-ios-firebase:
	bundle exec fastlane ios deploy_firebase bump:$(BUMP)

deploy-ios-testflight:
	bundle exec fastlane ios deploy_testflight bump:$(BUMP)

# =============================================================================
# Certificates & Signing
# =============================================================================
.PHONY: sync-certs sync-certs-appstore create-app

# Bundle ID for this environment, so the create-app gate names the identifier
# that is actually about to be claimed on App Store Connect.
APP_IDENTIFIER ?= $(shell sed -n 's/^[[:space:]]*APP_IDENTIFIER[[:space:]]*=[[:space:]]*//p' fastlane/env.$(ENV) 2>/dev/null | head -1)
APP_ID_OR_UNKNOWN = $(if $(APP_IDENTIFIER),$(APP_IDENTIFIER),unknown-bundle-id)

sync-certs:
	bundle exec fastlane ios sync_certs type:development

sync-certs-appstore:
	bundle exec fastlane ios sync_certs type:appstore

# Gated: App Store Connect records cannot be deleted, and the app name is
# unique across the whole store — a wrong one is permanent.
create-app:
	@bash scripts/confirm.sh "create $(APP_ID_OR_UNKNOWN)" \
		"Registers the bundle ID on the Developer Portal (API key) if missing," \
		"then creates a PERMANENT App Store Connect record for $(APP_ID_OR_UNKNOWN)." \
		"ASC apps cannot be deleted, and the app name is globally unique across" \
		"Apple's store — nobody, including you, can reuse it afterwards."
	bundle exec fastlane ios create_app

# =============================================================================
# Android Keystore
# =============================================================================
.PHONY: generate-keystore upload-keystore download-keystore

# Gated: a new keystore for an app already published under the old one makes
# every future upload rejected by Play ("not signed by the upload key").
generate-keystore:
	@bash scripts/confirm.sh "generate keystore $(ENV)" \
		"Generates a NEW Android signing keystore for env '$(ENV)'." \
		"If this app is already on the Play Store, uploads signed with a new key" \
		"are rejected and the only recovery is a Play support key reset." \
		"Set KEYSTORE_OVERWRITE=true as well to replace a keystore that exists."
	bundle exec fastlane android generate_keystore

upload-keystore:
	bundle exec fastlane android upload_keystore

download-keystore:
	bundle exec fastlane android download_keystore

# =============================================================================
# Full Setup
# =============================================================================
.PHONY: setup install

install:
	gem install bundler
	bundle install

setup: install infra-init infra-apply populate-secrets sync-certs sync-certs-appstore
	@echo ""
	@echo "Setup complete!"
	@echo "  - Infrastructure provisioned"
	@echo "  - Secrets populated"
	@echo "  - iOS certificates synced"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Confirm CodeStar connection in AWS Console"
	@echo "  2. Download google-services.json / GoogleService-Info.plist from Firebase Console"
	@echo "  3. Run 'make build-android' or 'make build-ios' to test locally"

# =============================================================================
# Help
# =============================================================================
.PHONY: help

help:
	@echo "Usage: make <target> [ENV=dev|staging|prod] [BUMP=patch|minor|major] [TRACK=internal|alpha|beta|production]"
	@echo ""
	@echo "Infrastructure:"
	@echo "  infra-init              Initialize Terraform"
	@echo "  infra-plan              Preview infrastructure changes"
	@echo "  infra-apply             Apply infrastructure (plans, shows it, then asks you"
	@echo "                          to type 'apply <ENV>'; AUTO_APPROVE=1 skips the prompt)"
	@echo "  infra-destroy           DESTRUCTIVE. Asks you to type 'destroy <project>-<ENV>'"
	@echo "  populate-secrets        Populate Secrets Manager values"
	@echo "  secrets-audit           Report secret age vs. rotation cadence (read-only)"
	@echo ""
	@echo "Build:"
	@echo "  build-android           Build Android APK"
	@echo "  build-ios               Build iOS IPA"
	@echo ""
	@echo "Deploy:"
	@echo "  deploy-android-firebase     Deploy to Firebase App Distribution"
	@echo "  deploy-android-play-store   Deploy to Google Play Store"
	@echo "  deploy-ios-firebase         Deploy to Firebase App Distribution"
	@echo "  deploy-ios-testflight       Deploy to TestFlight"
	@echo ""
	@echo "Signing:"
	@echo "  sync-certs              Sync development certificates (Match)"
	@echo "  sync-certs-appstore     Sync App Store certificates (Match)"
	@echo "  create-app              IRREVERSIBLE. Creates a permanent App Store Connect record"
	@echo "  generate-keystore       IRREVERSIBLE. Generates a new Android signing keystore"
	@echo "  upload-keystore         Upload keystore to S3"
	@echo ""
	@echo "Setup:"
	@echo "  install                 Install Ruby/Fastlane dependencies"
	@echo "  setup                   Full first-time setup"
	@echo ""
	@echo "Gated targets (infra-apply, infra-destroy, create-app, generate-keystore)"
	@echo "prompt for a confirmation phrase. See CLAUDE.md, \"Blast radius and"
	@echo "confirmation gates\". Agents must not answer these prompts for you."
