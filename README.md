# Personal AWS Landing Zone (Single Account)

A single-account simulation of an enterprise AWS landing zone — hub-and-spoke
networking, centralized logging, tag-based environment isolation, and a
detective security baseline. Built to mirror the concepts used in a real
multi-account Control Tower setup (Log Archive, Audit, Network Hub, Workload
accounts) without the cost or complexity of running multiple accounts.

## Architecture

```
                    ┌─────────────────────┐
                    │   Hub VPC (10.0.0.0/24)
                    │   IGW + NAT Gateway   │
                    │   (egress point)      │
                    └──────────┬────────────┘
                               │ Transit Gateway
              ┌────────────────┼────────────────┬───────────────┐
              │                │                │               │
        ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐   ┌─────▼─────┐
        │  Dev VPC  │    │ Test VPC  │    │ Prod VPC  │   │ Shared Svcs│
        │10.1.0.0/20│    │10.2.0.0/20│    │10.3.0.0/20│   │10.4.0.0/20 │
        └───────────┘    └───────────┘    └───────────┘   └───────────┘
```

| Enterprise concept | This lab's equivalent |
|---|---|
| Network Hub account | Hub VPC with IGW/NAT, all spoke egress routes through it via TGW |
| Log Archive account | Centralized S3 bucket, versioned, delete-denied, CloudTrail + Config delivery |
| Audit/Security account | GuardDuty + Security Hub with CIS Foundations v3.0.0 standard subscription. CIS Conformance Pack is NOT deployed by Terraform (see caveats) |
| SCPs at OU level | IAM permission boundaries per environment (dev/test/prod), with explicit `DenyOutsideHomeRegion`, `DenyCrossEnvironmentAccess`, and `DenyDisablingSecurityTooling` statements |
| Workload accounts | Dev/Test/Prod VPCs, isolated by tag-enforced IAM boundary + route tables |
| AWS Backup org policy | Tag-based backup plan/selection on `Environment=prod` resources |
| CI/CD via OIDC | GitHub Actions assumes a dedicated IAM role via OIDC (no long-lived keys), with `PowerUserAccess` plus a scoped IAM-management policy |

## Repo layout

```
landing-zone/
├── modules/
│   ├── vpc/                 # reusable VPC module (hub or spoke)
│   ├── transit-gateway/     # TGW + attachments + route propagation
│   ├── iam-boundaries/      # permission boundary + assumable role per env
│   ├── logging/             # S3 log bucket + CloudTrail + Config recorder
│   ├── security-baseline/   # GuardDuty + Security Hub (CIS standards sub)
│   ├── backup/              # AWS Backup plan, tag-based selection
│   └── github-oidc/         # GitHub OIDC provider + CI assume role
├── environments/
│   └── hub/                 # root module - the only one you `terraform apply`
├── scripts/
│   ├── 01.setup_s3-backend.sh   # one-shot bootstrap (bucket + secrets + OIDC role)
│   └── 02.destroy-s3-backend.sh # full teardown (OIDC module + bucket + GH bits)
└── .github/workflows/
    ├── terraform-plan-apply.yml # PR → plan; push to main → apply (env-gated)
    ├── drift-detection.yml      # daily plan; opens GH Issue on drift
    └── destroy.yml              # manual workflow_dispatch; state-rm OIDC then destroy
```

Only `environments/hub` is a root module in this single-account design —
since dev/test/prod here are VPCs (not separate AWS accounts), they're all
provisioned from the one root module rather than having their own state.

## Prerequisites

1. An AWS account with admin access (you, personally, for the lab)
2. Terraform >= 1.6 (CI pins 1.11.0)
3. AWS CLI configured (`aws configure` or SSO profile)
4. GitHub CLI (`gh`) authenticated (`gh auth login`) — only needed for the
   first-time bootstrap script, which writes repo secrets and creates the
   `production` environment

The remote-state bucket, versioning, Object Lock, encryption, GitHub
secrets, and the `production` environment are all created by the bootstrap
script — you don't need to provision them by hand. State locking uses the
**S3 native lockfile** (Terraform 1.10+, enabled via `use_lockfile = true`),
so there's no DynamoDB table.

## Setup

Bootstrap creates everything needed for the first `terraform apply`, then
once OIDC is in place all subsequent changes flow through pull requests.

### 1. One-shot bootstrap (creates state bucket + GH secrets + OIDC role)

```bash
./landing-zone/scripts/01.setup_s3-backend.sh
```

This script:
- Creates the `balraj-personal-lab-tfstate` S3 bucket (versioning, Object
  Lock in GOVERNANCE mode for 7 days, SSE-KMS, public access blocked)
- Writes the S3 backend block into `landing-zone/environments/hub/versions.tf`
- Sets the `TF_VAR_tf_state_bucket` repo secret
- Runs `terraform apply -target module.github_oidc` to create the GitHub
  Actions OIDC provider and `github-actions-landing-zone-role`
  - If the OIDC provider already exists in AWS (e.g. from a previous run or
    a CI destroy that did `terraform state rm`), the script detects it via
    `aws iam list-open-id-connect-providers` and runs `terraform import`
    before the targeted apply so it stays idempotent
- Sets the `AWS_GITHUB_OIDC_ROLE_ARN` repo secret from the role ARN output
- Creates the `production` GitHub environment

If `terraform init` hasn't been run yet, the OIDC step is skipped (no
state to apply against) — re-run the bootstrap after the first init.

### 2. First local apply (chicken-and-egg)

The OIDC role doesn't exist on the very first run, so the workflow can't
assume it yet. Run one apply locally with your own AWS credentials:

```bash
cd landing-zone/environments/hub
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: trusted principal ARNs, allowed branches, etc.

terraform init
terraform validate
terraform plan -out=tfplan.binary
terraform apply tfplan.binary
```

### 3. Configure the production environment reviewer

The bootstrap script creates the `production` GitHub Environment without
reviewers, so the `apply` job in `terraform-plan-apply.yml` is currently
ungated. Add yourself (or whoever should approve applies) as a required
reviewer in **Repo → Settings → Environments → production**.

### 4. From here on, everything goes through pull requests

- PR to `main` → `plan` job runs, diff posted as a PR comment and the
  plan is uploaded as a 5-day artifact
- Merge to `main` → `apply` job runs after you approve the `production`
  environment gate, applying the **exact** plan that was reviewed on the PR
- Daily at 22:00 UTC → `drift-detection.yml` runs `terraform plan
  -detailed-exitcode`; if anything has drifted out-of-band it opens a
  GitHub Issue labelled `drift`, `infrastructure`

## Known caveats / things to check before relying on this

- **CIS Conformance Pack is NOT in Terraform.** `modules/security-baseline/`
  only enables GuardDuty + Security Hub and subscribes to the CIS Foundations
  v3.0.0 standard. The conformance pack itself is intentionally omitted
  because AWS moved the S3 template URI; deploy it manually via
  `aws configservice put-conformance-pack` after `terraform apply` if you
  want the full Config rule set, or accept the Security Hub CIS standards
  subscription as the lab baseline.
- **Spoke → TGW routes are NOT applied.** `environments/hub/main.tf`
  composes the spoke VPCs and the TGW attachment but does not yet create
  the `aws_route` entries that point spoke private route tables at the
  TGW. This is a TODO in `main.tf` — it needs a two-apply pattern because
  `private_route_table_ids` is a computed output from the VPC module.
  Apply once without these routes, then re-add once the VPC IDs are
  stable in state. Until then, spoke ↔ spoke and spoke → internet traffic
  does not actually route through the hub.
- **VPC Flow Logs are disabled.** The root module does not pass
  `flow_log_destination_arn` to any VPC module invocation, so no Flow
  Logs are created. Wire the log bucket ARN in if you need them.
- **OIDC provider conflict on re-bootstrap.** AWS only allows one
  `token.actions.githubusercontent.com` OIDC provider per account. If one
  already exists in this account from another IaC stack, the bootstrap
  script's `terraform apply -target module.github_oidc` will fail with
  `EntityAlreadyExists`. The bootstrap script handles the in-stack case
  (imports the existing provider automatically). For cross-stack
  conflicts, import it yourself (commands are documented in
  `modules/github-oidc/main.tf`).
- **IAM permission boundary conditioning.** `DenyCrossEnvironmentAccess`
  only fires on resources already tagged with an `Environment` value.
  Untagged resources pass through — pair with a Config `required-tags`
  rule (not currently included) for full enforcement.
- **Permission boundaries only cover dev/test/prod.** The IAM boundaries
  module covers `["dev", "test", "prod"]` only; hub and shared-services
  resources inherit whatever the deploying principal has.
- **Single NAT Gateway**: cost-optimized for a lab (one NAT in the hub,
  not one per AZ). Single point of egress failure — acceptable for
  personal use, not for production.
- **Region lock**: the SCP-equivalent region-lock statement in the IAM
  boundary hardcodes `us-east-1`. Update if you're building in a
  different region.

## Teardown

The teardown script mirrors the bootstrap script — whatever
`01.setup_s3-backend.sh` creates, `02.destroy-s3-backend.sh` removes.

```bash
./landing-zone/scripts/02.destroy-s3-backend.sh
```

This script:
- Runs a **targeted** `terraform destroy -target module.github_oidc` to
  remove the OIDC provider, role, PowerUserAccess attachment, and inline
  IAM-management policy (only — the rest of the landing zone stays intact)
- Manual fallback: if the OIDC provider still exists in AWS (e.g. after a
  CI destroy that did `terraform state rm`), it finds any role trusting
  that provider, detaches its policies, deletes the role, then deletes
  the provider
- Deletes the `balraj-personal-lab-tfstate` S3 bucket (handles Object
  Lock bypass, all object versions + delete markers, incomplete multipart
  uploads, with two typed confirmations required)
- Removes the `TF_VAR_tf_state_bucket` and `AWS_GITHUB_OIDC_ROLE_ARN`
  GitHub repo secrets
- Deletes the `production` GitHub environment

To tear down the entire landing zone infrastructure as well (VPCs, TGW,
GuardDuty, etc.), run `cd landing-zone/environments/hub && terraform
destroy` manually after the teardown script completes.

## CI destroy workflow

`.github/workflows/destroy.yml` is a separate `workflow_dispatch`-only
job that destroys the **whole** landing zone. It has a deliberate
chicken-and-egg of its own: it runs as the OIDC role, so it can't let
Terraform destroy that role mid-run. The `plan` job therefore
`terraform state rm`s the four `module.github_oidc.*` resources first,
so they survive in AWS but are no longer tracked. To run CI again after
a CI destroy, either re-import the OIDC resources (see the comment in
`modules/github-oidc/main.tf`) or run `01.setup_s3-backend.sh` + a
local `terraform apply` to re-bootstrap from scratch.

If you ever need to change the OIDC role/trust policy itself, do that
one change via local `apply` again (you can't use a role to modify its
own trust policy cleanly via the same pipeline run).

Running this continuously (TGW attachments, NAT Gateway, Config, GuardDuty)
runs roughly **$80-120/month AUD** — mostly Transit Gateway attachment
hours and NAT Gateway. Run `./landing-zone/scripts/02.destroy-s3-backend.sh`
when not actively using it, or scale down to a single VPC for cheaper
day-to-day learning and only stand up the full hub-and-spoke when
practicing that specific scenario.

## Suggested learning path

1. Apply just the `vpc` + `transit-gateway` modules first, verify
   connectivity between spokes via the hub (ping test from an EC2 instance
   in each VPC)
2. Layer in `iam-boundaries`, test assuming the dev role and confirm it
   can't touch prod-tagged resources
3. Add `logging` + `security-baseline`, check CloudTrail/Config/GuardDuty
   findings in the console
4. Add `backup`, tag a test EC2 instance `Environment=prod`, confirm it
   gets picked up by the backup selection
5. Once comfortable, this maps directly to SAP-C02 exam scenarios on
   multi-account network design and AWS Organizations governance
