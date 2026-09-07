###############################################################################
# Camada 2 - Instalacao do ArgoCD (Kustomize puro, sem Helm)
#
# Rodar SOMENTE apos a camada raiz ter criado o cluster EKS e o kubeconfig:
#   cd terraform          && terraform init && terraform apply
#   aws eks update-kubeconfig --name togglemaster-eks --region us-east-1
#   cd terraform/argocd-install && terraform init && terraform apply
#
# Estado remoto proprio: s3://<bucket>/togglemaster/argocd.tfstate
###############################################################################
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "togglemaster-tfstate-248530551510"
    key          = "togglemaster/argocd.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
  }
}

provider "kustomization" {
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  context         = var.cluster_name
}

module "argocd" {
  source = "../modules/argocd"
}
