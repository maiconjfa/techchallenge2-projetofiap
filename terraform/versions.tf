###############################################################################
# ToggleMaster - Infraestrutura como Código (Fase 3)
#
# Backend remoto obrigatorio: estado NUNCA fica local.
#   - Bucket S3 criado por terraform/scripts/bootstrap-state.sh
#   - use_lockfile = true -> lock nativo do S3 (sem tabela DynamoDB),
#     disponivel a partir do Terraform >= 1.10
#
# Antes de rodar:
#   export AWS_PROFILE=tf
#   ../terraform/scripts/bootstrap-state.sh   (uma unica vez)
###############################################################################
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "togglemaster-tfstate-248530551510"
    key          = "togglemaster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "lab"
    }
  }
}
