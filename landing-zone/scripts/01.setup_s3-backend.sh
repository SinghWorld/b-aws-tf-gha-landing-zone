#!/usr/bin/env bash
###############################################################################
# scripts/01.setup_s3-backend.sh
# Run ONCE locally before `terraform init`
# Creates the S3 bucket used to store Terraform remote state.
# Features: Object Lock (WORM), fixed bucket naming, auto-backend config.
###############################################################################

set -euo pipefail

# ---- CONFIGURATION ----
AWS_REGION="us-east-1"

# Fixed bucket name for Terraform state
BUCKET_NAME="balraj-personal-lab-tfstate"

# Detect repo owner and name dynamically via gh CLI
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  GITHUB_FULL_NAME=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
  GITHUB_ORG=$(echo "$GITHUB_FULL_NAME" | cut -d/ -f1)
  GITHUB_REPO=$(echo "$GITHUB_FULL_NAME" | cut -d/ -f2)
else
  GITHUB_ORG="SinghWorld"
  GITHUB_REPO="b-aws-tf-gha-landing-zone"
fi

echo "==================================================================="
echo "  b-aws-tf-gha-landing-zone — State Bucket Bootstrap"
echo "  Account : $(aws sts get-caller-identity --query Account --output text)"
echo "  Bucket  : $BUCKET_NAME"
echo "  Region  : $AWS_REGION"
echo "==================================================================="

# ── Check AWS CLI is available ────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
  echo "❌  AWS CLI not found. Install it first: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  exit 1
fi

# ── Write Terraform versions.tf with bucket name ──────────────────────────────────
echo ""
echo "📝  Updating Terraform backend config in versions.tf..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_VERSIONS_FILE="$SCRIPT_DIR/../environments/hub/versions.tf"
mkdir -p "$(dirname "$TF_VERSIONS_FILE")"
cat > "$TF_VERSIONS_FILE" <<EOF
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "$BUCKET_NAME"
    key          = "landing-zone/terraform.tfstate"
    region       = "$AWS_REGION"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "personal-landing-zone"
      ManagedBy = "terraform"
    }
  }
}
EOF
echo "   Updated $TF_VERSIONS_FILE"

# ── Check bucket already exists ──────────────────────────────────────────────
BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "✅  Bucket '$BUCKET_NAME' already exists — versions.tf updated."
  BUCKET_EXISTS=true
fi

if [ "$BUCKET_EXISTS" = false ]; then
  # ── Create S3 Bucket ─────────────────────────────────────────────────────────
  echo ""
  echo "📦  Creating S3 bucket..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" || true
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" || true
  fi

  # ── Enable versioning (required for Object Lock) ─────────────────────────────
  echo "🔒  Enabling versioning..."
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  # ── Enable Object Lock (WORM protection) ─────────────────────────────────────
  echo "🔐  Enabling Object Lock (GOVERNANCE, 7 days)..."
  aws s3api put-object-lock-configuration \
    --bucket "$BUCKET_NAME" \
    --object-lock-configuration '{"ObjectLockEnabled": "Enabled", "Rule": {"DefaultRetention": {"Mode": "GOVERNANCE", "Days": 7}}}'

  # ── Enable server-side encryption ────────────────────────────────────────────
  echo "🔐  Enabling server-side encryption..."
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'

  # ── Block public access ───────────────────────────────────────────────────────
  echo "🚫  Blocking public access..."
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# ── Add TF_VAR_tf_state_bucket secret to GitHub Actions ──────────────────────
echo ""
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo "🔑  Adding TF_VAR_tf_state_bucket secret to GitHub Actions..."
  if gh secret set TF_VAR_tf_state_bucket --body "$BUCKET_NAME" \
       --repo "$GITHUB_ORG/$GITHUB_REPO"; then
    echo "   ✅  Secret set: TF_VAR_tf_state_bucket = $BUCKET_NAME"
  else
    echo "   ❌  Failed to set TF_VAR_tf_state_bucket secret."
  fi
else
  echo "ℹ️   GitHub CLI not available. Set TF_VAR_tf_state_bucket manually:"
  echo "    gh secret set TF_VAR_tf_state_bucket --body '$BUCKET_NAME'"
fi

# ── Create OIDC role for GitHub Actions via Terraform (targeted apply) ───────
echo ""
echo "🔧  Setting up GitHub OIDC role..."
TF_DIR="$SCRIPT_DIR/../environments/hub"

if command -v terraform &>/dev/null && [ -f "$TF_DIR/.terraform.lock.hcl" ]; then
  cd "$TF_DIR"

  # Check if state bucket is accessible
  if terraform state pull >/dev/null 2>&1; then
    echo "   Running targeted terraform apply for github_oidc module..."
    terraform apply -target module.github_oidc -auto-approve 2>&1 || true

    # Get the role ARN from terraform output
    GITHUB_OIDC_ROLE_ARN=$(terraform output -raw github_actions_role_arn 2>/dev/null || echo "")

    if [ -n "$GITHUB_OIDC_ROLE_ARN" ]; then
      echo "   ✅  OIDC role created: $GITHUB_OIDC_ROLE_ARN"
    else
      echo "   ⚠️  Could not get OIDC role ARN from terraform output."
      echo "   It will be available after full terraform apply."
    fi
  else
    echo "   ℹ️  Terraform state not accessible. Run full terraform apply first."
    GITHUB_OIDC_ROLE_ARN=""
  fi

  cd "$SCRIPT_DIR"
else
  echo "ℹ️   Terraform not initialized. Skipping OIDC role creation."
  GITHUB_OIDC_ROLE_ARN=""
fi

# ── Add AWS_GITHUB_OIDC_ROLE_ARN secret to GitHub Actions ────────────────────
echo ""
if [ -n "$GITHUB_OIDC_ROLE_ARN" ] && command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo "🔑  Adding AWS_GITHUB_OIDC_ROLE_ARN secret to GitHub Actions..."
  if gh secret set AWS_GITHUB_OIDC_ROLE_ARN --body "$GITHUB_OIDC_ROLE_ARN" \
       --repo "$GITHUB_ORG/$GITHUB_REPO"; then
    echo "   ✅  Secret set: AWS_GITHUB_OIDC_ROLE_ARN = $GITHUB_OIDC_ROLE_ARN"
  else
    echo "   ❌  Failed to set AWS_GITHUB_OIDC_ROLE_ARN secret."
  fi
else
  if [ -z "$GITHUB_OIDC_ROLE_ARN" ]; then
    echo "ℹ️   OIDC role ARN not available yet. Set AWS_GITHUB_OIDC_ROLE_ARN manually"
    echo "    after running full terraform apply."
  fi
fi

# ── Create production GitHub environment ────────────────────────────────────
echo ""
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo "🔗  Creating/verifying production environment..."
  if gh api repos/"$GITHUB_ORG/$GITHUB_REPO"/environments/production -X PUT -F wait_timer=0 >/dev/null 2>&1; then
    echo "   ✅  Environment 'production' created/updated"
  else
    echo "   ❌  Failed to create production environment."
  fi
else
  echo "ℹ️   GitHub CLI not available. Create 'production' environment manually."
fi

echo ""
echo "==================================================================="
echo "✅  Bootstrap complete!"
echo "    Bucket   : s3://$BUCKET_NAME"
echo "    Backend  : $TF_VERSIONS_FILE"
echo "    Secret   : TF_VAR_tf_state_bucket = $BUCKET_NAME"
if [ -n "$GITHUB_OIDC_ROLE_ARN" ]; then
  echo "    Secret   : AWS_GITHUB_OIDC_ROLE_ARN = $GITHUB_OIDC_ROLE_ARN"
fi
echo "    Note     : Uses S3 native lockfile (no DynamoDB)"
echo ""
echo "Next step → run: cd environments/hub && terraform init"
echo "==================================================================="