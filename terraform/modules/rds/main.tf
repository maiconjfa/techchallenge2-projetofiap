###############################################################################
# RDS PostgreSQL - uma instancia por microsservico de dominio:
#   auth_db, flag_db, targeting_db
###############################################################################

terraform {
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

locals {
  databases = ["auth_db", "flag_db", "targeting_db"]
}
