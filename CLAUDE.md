# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a **single-account AWS landing zone** built with Terraform, simulating an enterprise multi-account setup (Control Tower) for a personal lab. All resources live in one AWS account but are logically separated via VPCs, route tables, IAM permission boundaries, and tags.

### Hub-and-Spoke Network Topology

```
Hub VPC (10.0.0.0/24) — IGW + NAT Gateway (single point of egress)
 ├── Dev VPC (10.1.0.0/20)
 ├── Test VPC (10.2.0.0/20)
 ├── Prod VPC (10.3.0.0/20)
 └── Shared Services VPC (10.4.0.0/20)
```

All spokes route 0.0.0.0/0 through the Transit Gateway to the Hub for centralized egress. The Hub routes back to each spoke via explicit TGW routes.

### Module Boundaries (Enterprise Concept Analogy)

| Enterprise Concept | Implementation |
|---|---|
| Network Hub account | Hub VPC with IGW/NAT, spoke egress through TGW |
| Log Archive account | Centralized S3 bucket (versioned, encrypted, delete-protected), CloudTrail + Config delivery |
| Audit/Security account | GuardDuty + Security Hub + CIS conformance pack |
| SCPs at OU level | IAM permission boundaries per environment (dev/test/prod) with cross-environment deny |
| Workload accounts | VPCs isolated by tag-enforced IAM boundary + route tables |
| AWS Backup org policy | Tag-based backup on `Environment=prod` resources |
| GitHub Actions OIDC | IAM role assumed via OIDC — no long-lived AWS keys |

### Repo Layout

```
landing-zone/
├── modules/
│   ├── vpc/                 # Reusable VPC (hub or spoke). Public/private subnets, IGW, NAT, flow logs
│   ├── transit-gateway/     # TGW + per-VPC attachments + hub→spoke / spoke→hub routes
│   ├── iam-boundaries/      # Permission boundary policy + assumable role per env; cross-env deny
│   ├── logging/             # S3 log bucket (versioned, encrypted, lifecycle), CloudTrail, Config
│   ├── security-baseline/   # GuardDuty, Security Hub (CIS v1.4.0), CIS conformance pack
│   ├── backup/              # AWS Backup vault + plan + tag-based selection
│   └── github-oidc/         # OIDC identity provider + role for GitHub Actions workflows
├── environments/
│   └── hub/                 # Root module — the only one you `terraform apply`
└── .github/workflows/
    ├── terraform-plan-apply.yml  # PR → plan, merge to main → apply (production environment gate)
    └── drift-detection.yml       # Daily scheduled plan, opens GitHub Issue on drift
```

Only `environments/hub` is a root module. Dev/test/prod are VPCs within this account (not separate AWS accounts), so they're provisioned from the one root module.

### Key Configuration Details

- **Region**: `us-east-1` (hardcoded in IAM boundary region-lock and in Github Action Workflows)
- **GitHub repo**: `SinghWorld/b-aws-tf-gha-landing-zone`
- **State backend**: S3 (`balraj-personal-lab-tfstate`) + DynamoDB (`terraform-state-lock`) in `us-east-1`
- **Terraform**: >= 1.6.0, AWS provider ~> 5.0
- **CI/CD**: Terraform 1.7.5 pinned in workflows
- **IAM role trust**: Only `main` branch pushes and PRs can assume the OIDC role
- **IAM cross-environment deny**: Blocks ec2/rds/s3/dynamodb actions on resources tagged with a different `Environment` value
- **Security tooling protection**: IAM boundary denies disabling CloudTrail, Config, GuardDuty, Security Hub
- **Backup**: Daily at 03:00 UTC, 35-day retention, tags `Environment=prod`

## Common Commands

```bash
# Initialize the working directory
cd environments/hub
terraform init

# Format and validate
terraform fmt --recursive
terraform validate

# Plan and apply
terraform plan -out=tfplan.binary
terraform apply tfplan.binary

# Destroy everything
terraform destroy
```

## Bootstrap Process (chicken-and-egg)

GitHub Actions workflows need an AWS role to exist, but that role is created by this Terraform. Bootstrap once locally:

1. `cd environments/hub && cp terraform.tfvars.example terraform.tfvars` — edit with your IAM user ARN, log bucket name, and GitHub repo details
2. `terraform init && terraform apply`
3. `terraform output github_actions_role_arn` — add as GitHub repo secret `AWS_GITHUB_OIDC_ROLE_ARN`
4. Create a GitHub Environment named `production` with yourself as a required reviewer (this gates `apply`)
5. After this, all changes happen via PRs and pushes — the OIDC role handles auth

If you ever need to modify the OIDC role/trust policy itself, apply that change locally (you can't use the role to modify its own trust policy via the pipeline).

## Caveats

- **Conformance pack S3 URI**: Points to an AWS-managed template path that AWS periodically relocates. If `apply` fails with a 404 on the conformance pack, check the [current CIS template path](https://docs.aws.amazon.com/config/latest/developerguide/conformancepack-sample-templates.html).
- **IAM boundary limitation**: The `DenyCrossEnvironmentAccess` statement only triggers on resources already tagged `Environment`. Untagged resources slip through — pair with a Config rule for real enforcement.
- **Single NAT Gateway**: Cost-optimized for a lab; single point of failure for egress.
- **Monthly cost**: ~$80-120 AUD running continuously (TGW attachments + NAT Gateway are the main costs). Destroy when not in use.