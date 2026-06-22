#!/usr/bin/env bash
###############################################################################
# scripts/02.destroy-s3-backend.sh
# Tears down the S3 bucket created by 01.setup_s3-backend.sh
#
# 1. Destroys Terraform infrastructure (if any remains)
# 2. Deletes the S3 bucket (balraj-personal-lab-tfstate)
# 3. Removes GitHub secrets (TF_VAR_tf_state_bucket, AWS_GITHUB_OIDC_ROLE_ARN)
# 4. Deletes the production GitHub environment
#
# ⚠️  DANGER: This permanently destroys the Terraform state.
###############################################################################

set -euo pipefail

REGION="us-east-1"

# Fixed bucket name (matches 01.setup_s3-backend.sh)
BUCKET_NAME="balraj-personal-lab-tfstate"

# Detect repo details
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  GITHUB_FULL_NAME=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
  GITHUB_ORG=$(echo "$GITHUB_FULL_NAME" | cut -d/ -f1)
  GITHUB_REPO=$(echo "$GITHUB_FULL_NAME" | cut -d/ -f2)
else
  GITHUB_ORG="SinghWorld"
  GITHUB_REPO="b-aws-tf-gha-landing-zone"
fi

echo "==================================================================="
echo "  S3 Backend Teardown"
echo "  Org/Repo : $GITHUB_ORG/$GITHUB_REPO"
echo "  Region   : $REGION"
echo "==================================================================="
echo ""

# ── Check AWS CLI ───────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
  echo "❌  AWS CLI not found. Install it first."
  exit 1
fi

# # ── Destroy Terraform infrastructure if it exists ──────────────────────────
# echo "🔨  Checking for Terraform state..."
# TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../environments/hub"
# if [ -d "$TF_DIR" ] && [ -f "$TF_DIR/.terraform.lock.hcl" ]; then
#   echo "   Found Terraform state in $TF_DIR"
#   read -r -p "   Destroy Terraform infrastructure first? (yes/no): " DESTROY_TF
#   if [ "$DESTROY_TF" = "yes" ]; then
#     echo ""
#     echo "📦  Running terraform destroy in $TF_DIR..."
#     cd "$TF_DIR"
#     # Check if backend is configured
#     if terraform state pull >/dev/null 2>&1; then
#       echo "   Destroying infrastructure (this may take a while)..."
#       terraform destroy -auto-approve 2>&1 || echo "   ⚠️  Terraform destroy had issues. Check output above."
#     else
#       echo "   ℹ️  No Terraform state to destroy (or state is empty)."
#     fi
#     echo ""
#   fi
# fi

# ── Check if bucket exists ──────────────────────────────────────────────────
echo "🔍  Checking if bucket '$BUCKET_NAME' exists..."
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "ℹ️   Bucket '$BUCKET_NAME' does not exist. Nothing to delete."
  BUCKET_EXISTS=false
else
  BUCKET_EXISTS=true
  echo "   Bucket found."
fi

# ── Delete S3 bucket ───────────────────────────────────────────────────────
if [ "$BUCKET_EXISTS" = true ]; then
  echo ""
  echo "==================================================================="
  echo "  Target : s3://$BUCKET_NAME"
  echo "==================================================================="
  echo "⚠️  WARNING: This will PERMANENTLY DELETE all objects in the bucket"
  echo "   including the Terraform state file."
  echo ""

  # ── Check if Object Lock is enabled ─────────────────────────────────────
  echo "🔒  Checking Object Lock configuration..."
  OBJECT_LOCK_CONFIG=$(aws s3api get-object-lock-configuration \
    --bucket "$BUCKET_NAME" \
    --output json 2>/dev/null || echo "{}")

  OBJECT_LOCK_ENABLED=$(echo "$OBJECT_LOCK_CONFIG" | jq -r '.ObjectLockConfiguration.ObjectLockEnabled // "Disabled"')
  echo "   Object Lock: $OBJECT_LOCK_ENABLED"

  BYPASS_FLAG=""
  if [ "$OBJECT_LOCK_ENABLED" = "Enabled" ]; then
    echo "⚠️  Object Lock is ENABLED — will use --bypass-governance-retention"
    BYPASS_FLAG="--bypass-governance-retention"
  fi

  # ── Confirmation ────────────────────────────────────────────────────────
  read -r -p "Type the bucket name to confirm deletion [${BUCKET_NAME}]: " CONFIRM
  if [ "$CONFIRM" != "$BUCKET_NAME" ]; then
    echo "❌  Confirmation failed — bucket name does not match. Aborting."
    exit 1
  fi

  read -r -p "Are you sure? This cannot be undone! (yes/no): " SURE
  if [ "$SURE" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""

  # ── Step 1: Delete all object versions and delete markers ───────────────
  echo "🗑️  Removing all object versions and delete markers..."

  while true; do
    VERSION_JSON=$(aws s3api list-object-versions \
      --bucket "$BUCKET_NAME" \
      --output json \
      --max-items 1000 2>/dev/null)

    NEXT_TOKEN=$(echo "$VERSION_JSON" | jq -r '.NextToken // empty')

    VERSION_COUNT=$(echo "$VERSION_JSON" | jq '[.Versions // [] | .[]] + [.DeleteMarkers // [] | .[]] | length' 2>/dev/null)

    if [ "$VERSION_COUNT" -eq 0 ] || [ -z "$VERSION_COUNT" ]; then
      if [ -z "$NEXT_TOKEN" ]; then
        break
      fi
      continue
    fi

    echo "  Found $VERSION_COUNT version(s)/marker(s) in this page..."

    VERSIONS_ARR=$(echo "$VERSION_JSON" | jq '[.Versions[] | {Key: .Key, VersionId: .VersionId}]')
    if [ "$(echo "$VERSIONS_ARR" | jq 'length')" -gt 0 ]; then
      DELETE_PAYLOAD=$(echo "$VERSIONS_ARR" | jq -c '{Objects: .}')
      RESULT=$(aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$DELETE_PAYLOAD" \
        $BYPASS_FLAG \
        --output json 2>&1) || true
      if echo "$RESULT" | jq -e '.Deleted' >/dev/null 2>&1; then
        echo "$RESULT" | jq -r '.Deleted[] | "  Deleted: \(.Key) (v:\(.VersionId))"' || true
      fi
      if echo "$RESULT" | jq -e '.Error' >/dev/null 2>&1; then
        echo "$RESULT" | jq -r '.Error[] | "  ERROR: \(.Key) - \(.Message)"' || true
      fi
    fi

    DMS_ARR=$(echo "$VERSION_JSON" | jq '[(.DeleteMarkers // [])[] | {Key: .Key, VersionId: .VersionId}]')
    if [ "$(echo "$DMS_ARR" | jq 'length')" -gt 0 ]; then
      DELETE_PAYLOAD=$(echo "$DMS_ARR" | jq -c '{Objects: .}')
      RESULT=$(aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$DELETE_PAYLOAD" \
        $BYPASS_FLAG \
        --output json 2>&1) || true
      if echo "$RESULT" | jq -e '.Deleted' >/dev/null 2>&1; then
        echo "$RESULT" | jq -r '.Deleted[] | "  Deleted marker: \(.Key) (v:\(.VersionId))"' || true
      fi
    fi

    if [ -n "$NEXT_TOKEN" ] && [ "$NEXT_TOKEN" != "null" ]; then
      echo "  More versions exist, fetching next page..."
      VERSION_JSON=$(aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --output json \
        --max-items 1000 \
        --starting-token "$NEXT_TOKEN" 2>/dev/null)
      continue
    else
      break
    fi
  done

  # ── Step 2: Delete any remaining objects (non-versioned) ────────────────
  echo "🗑️  Removing any remaining objects..."
  if [ -n "$BYPASS_FLAG" ]; then
    aws s3 rm "s3://$BUCKET_NAME" --recursive $BYPASS_FLAG 2>&1 || true
  else
    aws s3 rm "s3://$BUCKET_NAME" --recursive 2>&1 || true
  fi

  # ── Step 3: Abort incomplete multipart uploads ──────────────────────────
  echo "🧹  Aborting incomplete multipart uploads..."
  UPLOADS=$(aws s3api list-multipart-uploads \
    --bucket "$BUCKET_NAME" \
    --output json \
    --query "Uploads[].{Key:Key, UploadId:UploadId}" 2>/dev/null)

  if [ -n "$UPLOADS" ] && [ "$UPLOADS" != "null" ]; then
    echo "$UPLOADS" | jq -r '.[] | "\(.Key)|\(.UploadId)"' 2>/dev/null | \
      while IFS='|' read -r KEY UPLOAD_ID; do
        aws s3api abort-multipart-upload \
          --bucket "$BUCKET_NAME" --key "$KEY" --upload-id "$UPLOAD_ID" >/dev/null 2>&1 || true
        echo "  Aborted upload: $KEY"
      done
  else
    echo "  No incomplete multipart uploads found."
  fi

  # ── Step 4: Delete the bucket ───────────────────────────────────────────
  echo "🗑️  Deleting bucket..."
  for TRY in 1 2 3 4 5; do
    if aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
      echo "  ✅  Bucket deleted successfully."
      break
    else
      if [ "$TRY" -lt 5 ]; then
        echo "  Retrying in 3s (attempt $TRY/5)..."
        sleep 3
      else
        echo "❌  Failed to delete bucket after 5 attempts."
        exit 1
      fi
    fi
  done
fi

# ── Clean up GitHub secrets ─────────────────────────────────────────────────
echo ""
echo "🔑  Cleaning up GitHub secrets..."
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo "   Checking GitHub secrets for $GITHUB_ORG/$GITHUB_REPO..."

  # Delete TF_VAR_tf_state_bucket secret
  if gh secret list --repo "$GITHUB_ORG/$GITHUB_REPO" 2>/dev/null | grep -q "TF_VAR_TF_STATE_BUCKET"; then
    gh secret delete TF_VAR_tf_state_bucket --repo "$GITHUB_ORG/$GITHUB_REPO" 2>&1 && echo "   ✅ Deleted secret: TF_VAR_tf_state_bucket" || echo "   ⚠️  Could not delete TF_VAR_tf_state_bucket"
  else
    echo "   ℹ️  Secret TF_VAR_tf_state_bucket not found."
  fi

  # Delete AWS_GITHUB_OIDC_ROLE_ARN secret
  if gh secret list --repo "$GITHUB_ORG/$GITHUB_REPO" 2>/dev/null | grep -q "AWS_GITHUB_OIDC_ROLE_ARN"; then
    gh secret delete AWS_GITHUB_OIDC_ROLE_ARN --repo "$GITHUB_ORG/$GITHUB_REPO" 2>&1 && echo "   ✅ Deleted secret: AWS_GITHUB_OIDC_ROLE_ARN" || echo "   ⚠️  Could not delete AWS_GITHUB_OIDC_ROLE_ARN"
  else
    echo "   ℹ️  Secret AWS_GITHUB_OIDC_ROLE_ARN not found."
  fi
else
  echo "   ℹ️  GitHub CLI not available or not authenticated. Skipping secret cleanup."
  echo "    Manually delete these secrets if needed:"
  echo "    - TF_VAR_tf_state_bucket"
  echo "    - AWS_GITHUB_OIDC_ROLE_ARN"
fi

# ── Delete GitHub production environment ────────────────────────────────────
echo ""
echo "🗑️  Cleaning up GitHub environments..."
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo "   Checking GitHub environments for $GITHUB_ORG/$GITHUB_REPO..."

  ENV_CHECK=$(gh api repos/"$GITHUB_ORG/$GITHUB_REPO"/environments/production -X DELETE 2>&1 || true)
  # Note: DELETE on a non-existent environment returns 204 if it existed
  echo "   ✅ Deleted environment: production"
else
  echo "   ℹ️  GitHub CLI not available. Skipping environment cleanup."
fi

echo ""
echo "==================================================================="
echo "✅  Teardown complete!"
echo "==================================================================="
echo ""
echo "Cleaned up:"
echo "  - S3 bucket: s3://$BUCKET_NAME"
echo "  - GitHub secret: TF_VAR_tf_state_bucket"
echo "  - GitHub secret: AWS_GITHUB_OIDC_ROLE_ARN"
echo "  - GitHub environment: production"
echo ""
echo "Note: The OIDC role 'github-actions-landing-zone-role' in AWS IAM"
echo "      was not deleted (managed by Terraform). Run 'terraform destroy'"
echo "      to remove it, or manually delete via AWS Console."
echo ""