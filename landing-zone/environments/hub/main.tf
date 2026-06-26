data "aws_caller_identity" "current" {}

# ---------- Hub VPC (has public subnets, IGW, NAT - this is where egress/inspection happens) ----------
module "hub_vpc" {
  source = "../../modules/vpc"

  name                 = "hub"
  environment          = "hub"
  vpc_cidr             = "10.0.0.0/24"
  azs                  = var.azs
  public_subnet_cidrs  = ["10.0.0.0/27", "10.0.0.32/27"]
  private_subnet_cidrs = ["10.0.0.64/27", "10.0.0.96/27"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
}

# ---------- Spoke VPCs ----------
module "dev_vpc" {
  source = "../../modules/vpc"

  name                 = "dev"
  environment          = "dev"
  vpc_cidr             = "10.1.0.0/20"
  azs                  = var.azs
  private_subnet_cidrs = ["10.1.0.0/22", "10.1.4.0/22"]
  enable_nat_gateway   = false # egress routes via hub through the TGW
}

module "test_vpc" {
  source = "../../modules/vpc"

  name                 = "test"
  environment          = "test"
  vpc_cidr             = "10.2.0.0/20"
  azs                  = var.azs
  private_subnet_cidrs = ["10.2.0.0/22", "10.2.4.0/22"]
  enable_nat_gateway   = false
}

module "prod_vpc" {
  source = "../../modules/vpc"

  name                 = "prod"
  environment          = "prod"
  vpc_cidr             = "10.3.0.0/20"
  azs                  = var.azs
  private_subnet_cidrs = ["10.3.0.0/22", "10.3.4.0/22"]
  enable_nat_gateway   = false
}

module "shared_services_vpc" {
  source = "../../modules/vpc"

  name                 = "shared"
  environment          = "shared"
  vpc_cidr             = "10.4.0.0/20"
  azs                  = var.azs
  private_subnet_cidrs = ["10.4.0.0/22", "10.4.4.0/22"]
  enable_nat_gateway   = false
}

# ---------- Transit Gateway - connects hub + all spokes ----------
module "transit_gateway" {
  source = "../../modules/transit-gateway"

  name = "personal-lab-tgw"

  vpc_attachments = {
    hub    = { vpc_id = module.hub_vpc.vpc_id, subnet_ids = module.hub_vpc.private_subnet_ids }
    dev    = { vpc_id = module.dev_vpc.vpc_id, subnet_ids = module.dev_vpc.private_subnet_ids }
    test   = { vpc_id = module.test_vpc.vpc_id, subnet_ids = module.test_vpc.private_subnet_ids }
    prod   = { vpc_id = module.prod_vpc.vpc_id, subnet_ids = module.prod_vpc.private_subnet_ids }
    shared = { vpc_id = module.shared_services_vpc.vpc_id, subnet_ids = module.shared_services_vpc.private_subnet_ids }
  }

}



# ---------- Routes: spokes <-> hub via TGW ----------
# Spokes have no NAT of their own; their private route tables send 0.0.0.0/0 to
# the TGW. The TGW route table has a default route pointing at the hub
# (see modules/transit-gateway/main.tf), so all non-VPC-bound spoke traffic
# lands on the hub, hits NAT, and goes out to the internet.
# The hub's private route table already has 0.0.0.0/0 -> NAT (from the VPC
# module), so we only need to add explicit spoke CIDR routes pointing back
# into the TGW for return traffic from NAT to reach the originating spoke.

resource "aws_route" "spoke_default_to_tgw" {
  for_each = {
    dev    = module.dev_vpc.private_route_table_ids[0]
    test   = module.test_vpc.private_route_table_ids[0]
    prod   = module.prod_vpc.private_route_table_ids[0]
    shared = module.shared_services_vpc.private_route_table_ids[0]
  }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.tgw_id
}

resource "aws_route" "hub_to_spokes" {
  for_each = {
    dev    = module.dev_vpc.vpc_cidr
    test   = module.test_vpc.vpc_cidr
    prod   = module.prod_vpc.vpc_cidr
    shared = module.shared_services_vpc.vpc_cidr
  }
  route_table_id         = module.hub_vpc.private_route_table_ids[0]
  destination_cidr_block = each.value
  transit_gateway_id     = module.transit_gateway.tgw_id
}

# ---------- IAM permission boundaries (SCP equivalent for single account) ----------
module "iam_boundaries" {
  source = "../../modules/iam-boundaries"

  environments           = ["dev", "test", "prod"]
  trusted_principal_arns = var.trusted_principal_arns
}

# ---------- Centralized logging (Log Archive account equivalent) ----------
module "logging" {
  source = "../../modules/logging"

  account_id      = data.aws_caller_identity.current.account_id
  log_bucket_name = var.log_bucket_name
}

# ---------- Security baseline (Audit account equivalent) ----------
module "security_baseline" {
  source = "../../modules/security-baseline"

  config_recorder_name = module.logging.config_recorder_name
  delivery_s3_bucket   = module.logging.log_bucket_name
}

# ---------- Backup (reliability) ----------
module "backup" {
  source = "../../modules/backup"

  backup_tag_key   = "Environment"
  backup_tag_value = "prod"
}

# ---------- GitHub Actions OIDC - lets workflows assume an AWS role without stored keys ----------
module "github_oidc" {
  source = "../../modules/github-oidc"

  github_org       = var.github_org
  github_repo      = var.github_repo
  allowed_branches = ["main"]
}
