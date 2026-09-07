###############################################################################
# Networking: VPC, Internet Gateway, Subnets publicas/privadas, Route Tables
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
}

variable "availability_zones" {
  description = "Lista de AZs."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
