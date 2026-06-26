# Copy this file to terraform.tfvars and fill in your own values.
# terraform.tfvars should be in .gitignore - never commit real account details.

aws_region = "us-east-1"

azs = ["us-east-1a", "us-east-1b"]

# Your IAM user ARN - find it with: aws sts get-caller-identity
trusted_principal_arns = [
  "arn:aws:iam::373160674113:user/Terraform"
]

# Must be globally unique across ALL of S3 - add your own suffix
log_bucket_name = "balraj-personal-lab-log-archive-2026"

# Used to scope the GitHub Actions OIDC trust policy to your repo only
github_org  = "SinghWorld"
github_repo = "b-aws-tf-gha-landing-zone"
