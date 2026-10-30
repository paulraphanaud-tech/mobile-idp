# Secrets

Everything CI needs to build and ship lives in four AWS Secrets Manager paths,
**one set per environment**. The paths are derived from `var.environment` in
`infra/main.tf` (`local.secret_paths`) and mirrored by `secret_path()` in
`scripts/setup.sh` — the two must agree, or `make populate-secrets` writes
where CodeBuild is not reading.
This document says what each one holds, what an attacker gets if it leaks, how
often it should be re-issued, and which of them can ever be rotated
automatically.

Check current state at any time — read-only, safe to run repeatedly:

```bash
make secrets-audit ENV=dev
```

## How secrets reach a build

```
AWS Secrets Manager
   │  (resolved by CodeBuild at build start, via the CodeBuild service role)
   ▼
CodeBuild environment variables  (type = SECRETS_MANAGER)
   │  declared in infra/main.tf and in each buildspec's `secrets-manager:` block
   ▼
fastlane, which reads them from ENV
```

Two consequences worth knowing:

- **Buildspecs deliberately have no `secrets-manager:` block.** That section
  is a static mapping with no variable expansion, so it cannot name
  `staging/fastlane/credentials` — one repo has one buildspec but several
  environments. All secrets are injected by the CodeBuild *project* instead
  (`secrets_manager_variables` in `infra/main.tf`), which is the only
  env-aware place to put them.
- **A missing key fails the build before any phase runs.** CodeBuild resolves
  every `SECRETS_MANAGER` variable at startup. If a path or a key inside it
  does not exist, the build fails immediately with no log output from your
  code. `make secrets-audit` flags secrets that exist but were never
  populated, which is the usual cause.
- **No static AWS credentials are involved anywhere.** Builds authenticate to
  S3 and Secrets Manager with the CodeBuild service role's temporary
  credentials (`modules/terraform/iam/main.tf`). There is no IAM user, no
  access key, and no `aws configure` in either buildspec — verified. Local
  developer runs use `AWS_PROFILE` from `fastlane/env.<env>`, which never
  applies in CI.

## The four secret paths

### 1. `<env>/fastlane/config` — app configuration

| | |
|---|---|
| **Contains** | `FLAVOR`, `SCHEME`, `FIREBASE_APP_ANDROID`, `FIREBASE_APP_IOS`, `APP_STORE_TESTER_GROUP`, `AWS_REGION` |
| **Blast radius if leaked** | Effectively none. These are identifiers, not credentials — a Firebase App ID is visible in any shipped binary. |
| **Rotation cadence** | None. Update when the app's configuration changes. |
| **Auto-rotatable** | Not applicable — nothing here is a credential. |

It lives in Secrets Manager only because CodeBuild's `SECRETS_MANAGER` env var
type is a convenient way to inject it. Treating it as a secret costs nothing,
but do not let its presence here imply it needs rotating.

### 2. `<env>/fastlane/credentials` — third-party credentials

| | |
|---|---|
| **Contains** | `FIREBASE_CLI_TOKEN`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_CONTENT`, `MATCH_PASSWORD` |
| **Blast radius if leaked** | **The worst of the four.** The ASC key is an App Manager credential: an attacker can upload builds to TestFlight, change app metadata, and manage certificates under your team. The Firebase token can distribute arbitrary builds to your testers. `MATCH_PASSWORD` decrypts every certificate and provisioning profile in the match bucket — combined with S3 read access, that is your signing identity. |
| **Rotation cadence** | **90 days.** |
| **Auto-rotatable** | **No** — see "Why these cannot be auto-rotated" below. |

### 3. `<env>/android/signing` — Android signing material

| | |
|---|---|
| **Contains** | `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` |
| **Blast radius if leaked** | An attacker can sign an APK that Android accepts as a genuine update to your app. Unlike every other secret here, **this cannot be fixed by rotating**: the key *is* the app's identity. Recovery means a Play upload-key reset, and for non-Play distribution, nothing. |
| **Rotation cadence** | **Passwords: 365 days. The key itself: never.** |
| **Auto-rotatable** | Passwords, partially — see below. The keystore, no. |

Note a redundancy worth resolving: `KEYSTORE_BASE64` is stored here *and* the
keystore file is stored in the `<project>-keystores` S3 bucket, and
`templates/buildspec.yaml` uses the S3 copy — it never reads `KEYSTORE_B64`.
The same signing key therefore sits in two places with two different access
paths. Picking one would halve the blast radius. (Left as a decision, not
changed: which copy is canonical depends on how you recover a lost keystore.)

### 4. `<env>/android/play_store` — Google Play service account

| | |
|---|---|
| **Contains** | `GOOGLE_PLAY_JSON_KEY_DATA` (a GCP service-account JSON key, including its private key) |
| **Blast radius if leaked** | Upload and release to your Play tracks under the service account's roles. Scope the account to "Release manager" on the single app, never project-wide. |
| **Rotation cadence** | **90 days.** |
| **Auto-rotatable** | **No** — the credential is issued by Google, not AWS. |

## Why these cannot be auto-rotated

AWS Secrets Manager's native rotation works by invoking a Lambda that talks to
the credential's *issuer* to mint a replacement, then swaps the version label.
That model fits credentials AWS itself issues (RDS passwords, IAM keys). It
does not fit any of the credentials here, for two distinct reasons:

**Reason 1 — the issuer is a third party with no programmatic issuance API.**

| Credential | Why not |
|---|---|
| App Store Connect API key | Apple issues `.p8` keys only through the App Store Connect web UI, under a human account with 2FA. There is no API to mint one. The private key is downloadable exactly once, at creation — so even a human cannot re-fetch it, let alone a Lambda. |
| Firebase CLI token | Produced by `firebase login:ci`, an interactive OAuth consent flow in a browser against a human Google account. It is a refresh token bound to that human. |
| Google Play service account key | Google *does* have an API (`iam.serviceAccounts.keys.create`), so this one is technically automatable — but it requires a separate long-lived GCP credential to call it, which just moves the rotation problem to a credential outside AWS with the same blast radius. Not worth it at this scale. Google's recommended answer is Workload Identity Federation, below. |

**Reason 2 — rotating would break the thing it protects.**

| Credential | Why not |
|---|---|
| `MATCH_PASSWORD` | It is the symmetric key for everything already encrypted in the match bucket. Changing it does not re-encrypt them; it makes them undecryptable. Rotating it means `match nuke` + re-issuing every certificate and profile, which invalidates in-flight builds. It is rotated by a deliberate human procedure, not a Lambda. |
| Android keystore | The key is the app's permanent identity. See above. |

### What *could* be automated for `prod/android/signing`

The keystore itself must not change, but the passwords protecting it can. A
rotation Lambda would need to:

1. Read the current secret, `base64 -d` the keystore to a temp file.
2. `keytool -storepasswd` and `keytool -keypasswd` to set new passwords.
3. Re-encode and write the new version as `AWSPENDING`.
4. Verify by opening the keystore with the new passwords.
5. Promote `AWSPENDING` to `AWSCURRENT`.

Cost of doing it: a Lambda with a JDK layer (keytool is not in the base
runtime), VPC/network config, and a failure mode where a half-rotated secret
locks you out of your own signing key. Value: protects against a *stale
password*, while the keystore bytes sitting next to it in the same secret are
the thing that actually matters and cannot rotate at all.

**Recommendation: do not build it.** The effort is better spent removing the
duplicate keystore copy (see path 3 above) and tightening read access to the
keystore bucket. Revisit only if a compliance regime requires demonstrable
automated rotation.

### The direction that would actually help

For the Play Store credential specifically, **Workload Identity Federation**
removes the secret rather than rotating it: GCP is configured to trust the
CodeBuild role's identity token directly, and no service-account key exists to
leak. This is the only change in this document that reduces the number of
long-lived secrets rather than managing them. It is a real piece of work
(GCP-side pool/provider setup plus a fastlane auth change) and is listed as a
follow-up, not done.

## Audit trail

Secrets Manager records *when* a secret last changed (`LastChangedDate`, what
`make secrets-audit` reports) but not *who* changed it. For that, query
CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutSecretValue \
  --region eu-west-1
```

CloudTrail must be enabled in the account — this platform does not provision
it. If secret-change attribution matters to you, enabling an account-level
trail is a prerequisite, and is a follow-up item.

## Operational checklist

**When onboarding a new project**

- [ ] `make infra-apply ENV=<env>` creates the four secrets **empty**
- [ ] `make populate-secrets ENV=<env>` fills them
- [ ] `make secrets-audit ENV=<env>` — every row must read `ok` or `n/a`, none
      `EMPTY` or `NOT FOUND`
- [ ] Confirm the Play service account is scoped to one app, not project-wide

**Every 90 days (or when `make secrets-audit` says `STALE`)**

- [ ] Re-issue the App Store Connect key: ASC → Users and Access → Keys →
      revoke the old one *after* the new one is in Secrets Manager
- [ ] Re-issue the Firebase CI token: `firebase login:ci`
- [ ] Re-issue the Play service-account key in the GCP console
- [ ] `make populate-secrets ENV=<env>` and re-run the audit
- [ ] Run one build per platform to confirm nothing broke before revoking the
      old credentials

**When someone leaves the team**

- [ ] Re-issue everything in `<env>/fastlane/credentials` — the ASC key and Firebase
      token are bound to a human account and survive that person's departure
- [ ] Rotate `<env>/android/signing` **passwords** (not the key)
- [ ] Decide on `MATCH_PASSWORD`: rotating it means re-issuing all
      certificates. Usually only warranted if the departure was not amicable

**Never**

- [ ] Commit `fastlane/env.secret` (gitignored — keep it that way)
- [ ] Paste a secret into a terminal that is being screen-shared;
      `populate-secrets` hides credential input, but scrollback from other
      tools may not
- [ ] Let an AI agent populate a secret on your behalf

## Migrating from the pre-environment paths

Earlier versions used a fixed, inconsistent set of paths. If you have a
deployment on those, the rename is a create-and-destroy, not a move:

| Old | New (for `environment = "dev"`) |
|---|---|
| `dev/secret/fastlane` | `dev/fastlane/config` |
| `secret/env/fastlane` | `dev/fastlane/credentials` |
| `prod/android/signing` | `dev/android/signing` |
| `prod/android/play_store` | `dev/android/play_store` |

Procedure:

1. `make infra-plan ENV=dev` — confirm it shows 4 secrets to add and 4 to
   destroy, and nothing else unexpected.
2. Copy the current values out first; the old secrets enter a 7-day recovery
   window on destroy, but do not rely on that:
   ```bash
   for s in dev/secret/fastlane secret/env/fastlane prod/android/signing prod/android/play_store; do
     aws secretsmanager get-secret-value --secret-id "$s" \
       --query SecretString --output text > "backup-$(echo "$s" | tr / _).json"
   done
   ```
   Those files contain live credentials — delete them once you are done.
3. `make infra-apply ENV=dev`
4. `make populate-secrets ENV=dev`
5. `make secrets-audit ENV=dev` — every row `ok` or `n/a`
6. Run one build per platform before deleting the backups.
