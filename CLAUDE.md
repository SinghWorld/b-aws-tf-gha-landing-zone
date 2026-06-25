# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a **single-account AWS landing zone** built with Terraform, simulating an enterprise multi-account setup (Control Tower) for a personal lab. All resources live in one AWS account but are logically separated via VPCs, route tables, IAM permission boundaries, and tags.

### Hub-and-Spoke Network Topology

```
                     ┌─────────────────────┐
                     │   Hub VPC (10.0.0.0/24)
                     │   IGW + NAT Gateway  │
                     │   egress point       │
                     └──────────┬───────────┘
                                │ Transit Gateway
              ┌─────────────────┼─────────────────┬──────────────┐
        ┌─────▼─────┐     ┌─────▼─────┐    ┌─────▼─────┐  ┌─────▼─────┐
        │ Dev VPC   │     │ Test VPC  │    │ Prod VPC  │  │ Shared Svcs│
        │10.1.0.0/20│     │10.2.0.0/20│    │10.3.0.0/20│  │10.4.0.0/20 │
        └───────────┘     └───────────┘    └───────────┘  └───────────┘
```

Only `landing-zone/environments/hub` is the root module. Dev/test/prod are VPCs in this single account, so they're all provisioned from one root module rather than having separate state.

### Module Boundaries (Enterprise Concept Analogy)

| Enterprise Concept | Implementation |
|---|---|
| Network Hub account | Hub VPC with IGW/NAT, spoke egress via TGW |
| Log Archive account | Centralized S3 bucket (versioned, encrypted, delete-denied), CloudTrail + Config delivery |
| Audit/Security account | GuardDuty + Security Hub (CIS v3.0.0); CIS Conformance Pack deferred to manual CLI |
| SCPs at OU level | IAM permission boundaries per env (dev/test/prod) with cross-env deny |
| Workload accounts | VPCs isolated by tag-enforced IAM boundary + route tables |
| AWS Backup org policy | Tag-based backup plan on `Environment=prod` resources |
| GitHub Actions OIDC | IAM role assumed via OIDC — `PowerUserAccess` + scoped IAM mgmt, no long-lived keys |

### Repo Layout

```
landing-zone/
├── modules/
│   ├── vpc/                 # Reusable VPC (hub or spoke). Public/private subnets, IGW, NAT, flow logs
│   ├── transit-gateway/     # TGW + per-VPC attachments + associations/propagations to shared RT
│   ├── iam-boundaries/      # Permission boundary + `<env>-admin-role` per env; cross-env deny
│   ├── logging/             # S3 log bucket + multi-region CloudTrail + Config recorder/delivery
│   ├── security-baseline/   # GuardDuty + Security Hub CIS v3.0.0 subscription
│   ├── backup/              # AWS Backup vault + plan with tag-based selection
│   └── github-oidc/         # OIDC provider + role for GHA workflows (PowerUserAccess + IAM mgmt)
├── environments/
│   └── hub/                 # Only root module — terraform apply is run here
├── scripts/
│   ├── 01.setup_s3-backend.sh   # One-shot bootstrap: bucket + GH secrets + production env
│   └── 02.destroy-s3-backend.sh # Teardown: terraform destroy, bucket, secrets, env
└── .github/workflows/
    ├── terraform-plan-apply.yml  # PR → plan (artifact uploaded); push to main → apply (production env gate)
    └── drift-detection.yml       # Daily 22:00 UTC plan; opens GitHub Issue on drift
```

### Key Configuration Details

- **Region**: `us-east-1` (hardcoded in IAM boundary region-lock statement and in both GitHub workflows)
- **GitHub repo (per CI)**: `SinghWorld/b-aws-tf-gha-landing-zone`
- **State backend**: S3 (`balraj-personal-lab-tfstate`) in `us-east-1`, key `landing-zone/terraform.tfstate`, encrypted, **S3 native lockfile** (`use_lockfile = true`) — no DynamoDB
- **Terraform**: >= 1.6.0; AWS provider `~> 5.0`; CI pins `1.7.5`
- **Default tags on all resources**: `Project = personal-landing-zone`, `ManagedBy = terraform`
- **IAM trust restriction**: GitHub OIDC role only allows `main` pushes + any-branch PRs via `sub` claim conditions
- **IAM cross-environment deny** (`DenyCrossEnvironmentAccess`): Blocks `ec2:*`, `rds:*`, `s3:*`, `dynamodb:*` on resources tagged with a *different* `Environment` value than the assumed role's env
- **Security tooling protection** (`DenyDisablingSecurityTooling`): Denies `StopLogging`/`DeleteTrail`/`DeleteConfigRule`/`StopConfigurationRecorder`/`DeleteDetector`/`DisableSecurityHub`
- **Region lock** (`DenyOutsideHomeRegion`): Denies `ec2:*`/`rds:*` outside `us-east-1`
- **TGW design**: Single shared route table, all VPCs propagate; hub-key is `hub` (variable `hub_key`)
- **Backup defaults**: `cron(0 3 * * ? *)` (daily 03:00 UTC), 35-day retention, tag `Environment=prod`
- **Log bucket**: KMS encryption (`aws/s3`), 90d → STANDARD_IA, 180d → GLACIER, default 365d expiry, denies object deletion + non-TLS

## Common Commands

All Terraform work happens relative to `landing-zone/environments/hub/`.

```bash
# One-time bootstrap (creates S3 state bucket, sets GH secrets, creates production env)
./landing-zone/scripts/01.setup_s3-backend.sh

# Initialize, format, validate
cd landing-zone/environments/hub
terraform init
terraform fmt -recursive        # run from repo root or landing-zone/
terraform validate

# Plan and apply (local)
terraform plan -out=tfplan.binary
terraform apply tfplan.binary

# Destroy everything (infrastructure + state bucket + GH secrets + production env)
./landing-zone/scripts/02.destroy-s3-backend.sh
# ...or just the AWS resources:
cd landing-zone/environments/hub && terraform destroy
```

## Module Reference

### `modules/vpc/`
Reusable for hub or spoke. Public subnets (and thus IGW + NAT) are conditional on `public_subnet_cidrs` being non-empty. Hub gets IGW + single NAT (cost-optimized for lab); spokes pass empty `public_subnet_cidrs` and `enable_nat_gateway = false` because egress flows via TGW → hub. **Outputs** include `private_route_table_ids` for downstream TGW route propagation. Set `flow_log_destination_arn` to enable VPC Flow Logs (defaults `null`/disabled here — root module doesn't wire it up).

### `modules/transit-gateway/`
Creates one TGW, one shared route table, and a `aws_ec2_transit_gateway_vpc_attachment` per entry in `vpc_attachments` map. Disables default route table association/propagation on the TGW so we control routing explicitly. All attachments are associated with and propagate into the single shared route table.

### `modules/iam-boundaries/`
One permission boundary policy + one assumable role per env in `var.environments`. Each boundary contains 4 statements: `AllowWithinBoundary`, `DenyCrossEnvironmentAccess`, `DenyDisablingSecurityTooling`, `DenyOutsideHomeRegion`. Roles use `PowerUserAccess` and accept the boundary via `permissions_boundary` arg. Trust policy restricted to `var.trusted_principal_arns`.

### `modules/logging/`
S3 bucket with full hardening (versioning, public access block, SSE-KMS, lifecycle, deny-delete + deny-insecure-transport policy). CloudTrail is multi-region with log file validation. Config recorder/delivery + recorder-status. Two policy statements reference `aws_caller_identity` account ID baked into the policy at apply time.

### `modules/security-baseline/`
Currently only GuardDuty + Security Hub CIS v3.0.0 standards subscription. Takes `config_recorder_name` and `delivery_s3_bucket` as inputs but does NOT create the Config conformance pack (history: AWS moved the S3 template URI; create manually via `aws configservice put-conformance-pack` after apply — see comments in `main.tf`).

### `modules/backup/`
Backup vault + role (`AWSBackupServiceRolePolicyForBackup` + `…ForRestores`) + plan + tag-based selection on `Environment=prod`.

### `modules/github-oidc/`
Creates (or attempts to create — see caveat below) the GitHub OIDC provider and `github-actions-landing-zone-role`. Trust policy: `aud = sts.amazonaws.com` AND `sub` matches one of `repo:org/repo:ref:refs/heads/<branch>` for each `allowed_branches` OR `repo:org/repo:pull_request` for PRs. Inline IAM management policy grants scoped actions on top of `PowerUserAccess` (since `PowerUserAccess` excludes IAM and this repo manages IAM).

### `environments/hub/main.tf`
Composes all modules. The spokes currently have **no `aws_route` resource from spoke private RTs to the TGW** — main.tf carries a TODO note explaining this requires a two-apply pattern because `private_route_table_ids` is a computed output. Apply once without these, re-add once VPC IDs are stable.

## Key Cross-Module Wiring

- `environments/hub/main.tf` references modules in topological order: VPCs → TGW (uses VPC outputs) → IAM boundaries → logging (uses `data.aws_caller_identity`) → security baseline (uses logging outputs) → backup → github oidc
- IAM boundary variable `environments = ["dev", "test", "prod"]` — note that the **vpc modules** use environments `dev`, `test`, `prod`, `shared`, `hub`, while IAM boundaries only cover `dev`/`test`/`prod`. Shared/hub resources simply inherit whatever the deploying principal has; only the three workload envs are isolated.
- Outputs (`hub_vpc_id`, `spoke_vpc_ids`, `transit_gateway_id`, `environment_role_arns`, `github_actions_role_arn`, etc.) flow back to the root.

## Bootstrap Process (chicken-and-egg)

GitHub Actions needs an AWS role to exist, but the role is created by this Terraform. Two-phase bootstrap:

1. **Run `scripts/01.setup_s3-backend.sh` locally** — creates S3 state bucket (with Object Lock + SSE + versioning + PAB), writes `versions.tf`, sets `TF_VAR_tf_state_bucket` + `AWS_GITHUB_OIDC_ROLE_ARN` GitHub secrets, creates the `production` GitHub environment.
2. **Run `terraform init && terraform apply` once locally** in `environments/hub/` (chicken-and-egg: the first apply must use your own AWS creds because the OIDC role doesn't exist yet).
3. **Add a required reviewer** to the `production` GitHub Environment (the script creates it without reviewers) — this gates the `apply` job.
4. After this, all changes flow via PR → plan → merge to main → manual approval → apply.

If you need to modify the OIDC role/trust policy itself, apply that change locally — you can't use a role to modify its own trust policy via the same pipeline run.

## CI/CD Workflows

### `.github/workflows/terraform-plan-apply.yml`
- Triggered by: PR to `main` (paths filtered to `environments/hub/**` + `modules/**`), push to `main`, manual dispatch.
- `plan` job: init → validate → `terraform plan -out=tfplan.binary` → upload as `tfplan` artifact (5d retention).
- `apply` job: only runs on `push` to `main`. Depends on `plan` job. Downloads the artifact and runs `terraform apply -auto-approve tfplan.binary` against the **same plan that was reviewed on the PR**. Gated by `environment: production` (manual approval).
- Both jobs: `permissions: id-token: write` + `contents: read` + `pull-requests: write`; Terraform 1.7.5; OIDC via `secrets.AWS_GITHUB_OIDC_ROLE_ARN`.

### `.github/workflows/drift-detection.yml`
- Daily 22:00 UTC (== 8am AEST).
- Runs `terraform plan -detailed-exitcode`. Exit code 2 = drift → opens a GitHub Issue labeled `drift`, `infrastructure`.
- Required secrets: same OIDC role ARN; required permissions: `issues: write`.

## Caveats

- **CIS Conformance Pack**: NOT in Terraform. `terraform plan/apply` will not create it (see `modules/security-baseline/main.tf` comment block). Add manually after apply if desired, or accept the CIS standard subscription via Security Hub as a substitute baseline.
- **Spoke → TGW routes NOT applied**: spokes currently have no `aws_route` to the TGW, so inter-spoke and spoke→internet traffic does not actually route through the hub. Root `main.tf` has a TODO to add these once `private_route_table_ids` is stable in state. Apply once, then re-add.
- **OIDC provider creation**: AWS only allows one `token.actions.githubusercontent.com` OIDC provider per account. If you already have one in this account from another IaC stack, `terraform apply` will fail — import it as documented in `modules/github-oidc/main.tf` instead of letting Terraform recreate.
- **IAM boundary conditioning**: `DenyCrossEnvironmentAccess` only fires on resources already tagged with an `Environment` value. Untagged resources pass through — pair with a Config `required-tags` rule (not currently included) for full enforcement.
- **VPC Flow Logs disabled**: root module does not pass `flow_log_destination_arn` to any VPC module invocation, so no Flow Logs are created. Wire the log bucket ARN in if needed.
- **Single NAT Gateway**: single point of egress failure; cost-optimized for a lab.
- **Region lock**: `us-east-1` is hardcoded in IAM boundary; change if deploying elsewhere.
- **Monthly cost**: ~$80–120 AUD running continuously (TGW attachments + NAT are the biggest line items). Destroy with `scripts/02.destroy-s3-backend.sh` when not in use.

## Useful Pointers

- `landing-zone/README.md` — long-form overview with learning-path suggestions
- `landing-zone/environments/hub/outputs.tf` — what the root module exports (`github_actions_role_arn` is the one you paste into the GH secret)
- `scripts/01.setup_s3-backend.sh` — first-run bootstrap
- `scripts/02.destroy-s3-backend.sh` — full cleanup (handles Object Lock bypass)

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
