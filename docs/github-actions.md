# GitHub Actions

`scripts/generate-github-actions.sh` renders `templates/github/` into an app
repo. The `generate-github-actions` skill drives it conversationally, and the
`connect-app` skill uses it to take an app from "just written in a Claude chat"
to "compiled, tested and runnable" without anyone's own computer.

## Workflows

| File (in the app) | Trigger | Runner | Needs | Tier |
|---|---|---|---|---|
| `ios-ci.yml` | push, any branch; manual | macOS | nothing | 1 |
| `ios-preview.yml` | push to default branch; manual | macOS | optional `APPETIZE_API_TOKEN` secret, `APPETIZE_PUBLIC_KEY` variable | 1 |
| `ios-testflight.yml` | manual only (`environment`, `bump` inputs) | macOS | GitHub OIDC infra (below), GitHub environment with `AWS_ROLE_ARN`, populated `<env>/fastlane/credentials`, app record | 2 |
| `flutter-ci.yml` | push, any branch; manual | Linux | nothing | 1 |
| `.github/dependabot.yml` | monthly | — | keeps action versions current | — |

Design choices worth keeping:

- **CI listens to `push` only.** With `pull_request` as well, every PR runs
  twice. On a private repo macOS minutes count 10x against the free quota
  (2,000 → ~200 macOS minutes on GitHub Free), so duplicates are expensive.
  Every job has a `timeout-minutes` and a `cancel-in-progress` concurrency group.
- **CI uses `xcodebuild` directly**, not fastlane: no Ruby setup, no IDP
  checkout, nothing to sign — the fastest path to a red/green signal.
- **The simulator is picked at run time** (newest iOS runtime, first iPhone),
  so runner image updates don't break a hard-coded device name.
- **Test results** go to the job summary (`xcresulttool`); the `.xcresult`
  bundle is attached only on failure.

## Browser preview (Appetize)

`ios-preview.yml` builds an unsigned Debug simulator `.app`, zips it and, when
`APPETIZE_API_TOKEN` is set, uploads it to Appetize. The job summary links to
the app running in a browser — usable from a phone. The first upload creates
an app and prints its `publicKey`; save it as the repo variable
`APPETIZE_PUBLIC_KEY` so later runs update the same URL. Without a token the
zip is still attached as an artifact.

## TestFlight without static credentials

`ios-testflight.yml` assumes an AWS role through GitHub OIDC, reads
`<env>/fastlane/credentials` with `aws-secretsmanager-get-secrets`, checks out
mobile-idp into `.idp/`, and runs `fastlane ios deploy_testflight` (match
readonly → archive → upload, internal testers).

Infra (in the IDP stack of that environment):

```hcl
# infra/environments/dev/terraform.tfvars
github_actions_repositories = ["owner/app"]
# github_actions_environments = ["dev"]       # default: [environment]
# github_oidc_provider_arn    = "arn:aws:iam::…:oidc-provider/token.actions.githubusercontent.com"
#                                             # only if the provider already exists in the account
```

`make infra-plan ENV=dev`, then the user runs `make infra-apply ENV=dev`
(gated). `make infra-output ENV=dev` prints `github_actions_role_arn`.

The role (`modules/terraform/github_oidc`) trusts only
`repo:<owner>/<app>:environment:<env>` — jobs that declare that GitHub
environment — and can only `GetSecretValue` on the two fastlane secrets and
read the match bucket. Put required reviewers on the GitHub `prod` environment
to keep a human in front of production uploads.

In the app repo: Settings → Environments → `dev` → variable `AWS_ROLE_ARN`.
Set `APPLE_TEAM_ID` in `fastlane/env.dev`, and create the App Store Connect
record once (`make create-app`, gated — or in the App Store Connect web UI).

## Regenerating

Re-run the generator with `--force`. Action versions are pinned in one place
at the top of the script; dependabot bumps generated files in between.
