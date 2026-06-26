terraform {
  required_version = ">= 1.11.0"  # use_lockfile (S3 native state locking) became GA in 1.11.0

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "balraj-personal-lab-tfstate"
    key          = "landing-zone/terraform.tfstate"
    region       = "us-east-1"
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
