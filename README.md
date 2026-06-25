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
| Audit/Security account | GuardDuty + Security Hub + CIS conformance pack, all in this account |
| SCPs at OU level | IAM permission boundaries per environment (dev/test/prod) |
| Workload accounts | Dev/Test/Prod VPCs, isolated by tag-enforced IAM boundary + route tables |
| AWS Backup org policy | Tag-based backup plan/selection on `Environment=prod` resources |

## Repo layout

```
landing-zone/
├── modules/
│   ├── vpc/                 # reusable VPC module (hub or spoke)
│   ├── transit-gateway/     # TGW + attachments + route propagation
│   ├── iam-boundaries/      # permission boundary + assumable role per env
│   ├── logging/             # S3 log bucket + CloudTrail + Config recorder
│   ├── security-baseline/   # GuardDuty + Security Hub + conformance pack
│   └── backup/              # AWS Backup plan, tag-based selection
├── environments/
│   └── hub/                 # root module - the only one you `terraform apply`
└── .github/workflows/       # plan/apply + drift detection (OIDC auth)
```

Only `environments/hub` is a root module in this single-account design —
since dev/test/prod here are VPCs (not separate AWS accounts), they're all
provisioned from the one root module rather than having their own state.

## Prerequisites

1. An AWS account with admin access (you, personally, for the lab)
2. Terraform >= 1.6
3. AWS CLI configured (`aws configure` or SSO profile)
4. An S3 bucket + DynamoDB table for remote state (create once, manually or
   via a small bootstrap config), since the backend in `versions.tf` expects
   them to already exist:
   ```bash
   aws s3api create-bucket --bucket balraj-personal-lab-tfstate --region us-east-1 \
     --create-bucket-configuration LocationConstraint=us-east-1
   aws s3api put-bucket-versioning --bucket balraj-personal-lab-tfstate \
     --versioning-configuration Status=Enabled
   aws dynamodb create-table --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST --region us-east-1
   ```

## Setup

```bash
cd environments/hub
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: your IAM user ARN, a globally-unique log bucket name

terraform init
terraform validate
terraform plan
terraform apply
```

## Known caveats / things to check before relying on this

- **Conformance pack S3 URI** (`modules/security-baseline/main.tf`): points
  to an AWS-managed sample template path that was verified at time of
  writing. AWS periodically relocates these. If `terraform apply` fails on
  the conformance pack with an access/404 error, check the current path at
  the [AWS Config conformance pack docs](https://docs.aws.amazon.com/config/latest/developerguide/conformancepack-sample-templates.html)
  and update `template_s3_uri`.
- **IAM permission boundary cross-environment deny**: the `DenyCrossEnvironmentAccess`
  statement in `iam-boundaries` only triggers on resources that are already
  tagged with an `Environment` tag. Untagged resources slip through, so pair
  this with a Config rule (`required-tags`) for real enforcement — not
  included here to keep the lab's first pass simple.
- **Single NAT Gateway**: cost-optimized for a lab (one NAT, not one per AZ).
  This is a single point of failure for egress — acceptable for personal use,
  not for production.
- **Region lock**: the SCP-equivalent region-lock statement in the IAM
  boundary hardcodes `us-east-1`. Update if you're building in a
  different region.

## GitHub Actions setup (first-time bootstrap)

There's a chicken-and-egg problem: the workflows need an AWS role to exist
before they can run, but that role is created *by* this Terraform. Bootstrap
it once locally, then hand off to GitHub Actions for everything after.

1. **Apply once from your own machine** (with your AWS CLI credentials):
   ```bash
   cd environments/hub
   terraform init
   terraform apply
   ```
   This creates everything, including the GitHub OIDC provider and role.

2. **Grab the role ARN from the output:**
   ```bash
   terraform output github_actions_role_arn
   ```

3. **Add it as a GitHub repo secret:**
   - Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: `AWS_GITHUB_OIDC_ROLE_ARN`
   - Value: the ARN from step 2

4. **Create a GitHub Environment named `production`** (Settings → Environments)
   and add yourself as a required reviewer — this is what gates the `apply`
   job in `terraform-plan-apply.yml` behind manual approval.

5. **From here on, push to `main` or open a PR** and the workflows take over:
   - PR → `plan` runs automatically, shows the diff in the PR
   - Merge to `main` → `apply` runs after you approve the `production`
     environment gate
   - Daily → `drift-detection.yml` checks for manual console changes and
     opens a GitHub Issue if it finds any

If you ever need to change the OIDC role/trust policy itself, do that one
change via local `apply` again (you can't use a role to modify its own
trust policy permissions cleanly via the same pipeline run).



Running this continuously (TGW attachments, NAT Gateway, Config, GuardDuty)
runs roughly **$80-120/month AUD** — mostly Transit Gateway attachment
hours and NAT Gateway. Destroy with `terraform destroy` when not actively
using it, or scale down to a single VPC for cheaper day-to-day learning and
only stand up the full hub-and-spoke when practicing that specific scenario.

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
