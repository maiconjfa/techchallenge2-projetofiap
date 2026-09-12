###############################################################################
# ToggleMaster - composicao da infraestrutura (Fase 3)
#
# Ordem logica de dependencias (gerenciada pelo Terraform):
#   networking -> ecr / dynamodb / sqs -> eks -> rds / elasticache
#                                                \-> argocd (2a fase)
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# 1. Networking
###############################################################################
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = var.tags
}

###############################################################################
# 2. Repositorios ECR
###############################################################################
module "ecr" {
  source = "./modules/ecr"

  repository_names      = var.ecr_repository_names
  image_retention_count = var.ecr_image_retention_count
  tags                  = var.tags
}

###############################################################################
# 3. Bancos NoSQL / Mensageria
###############################################################################
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = var.dynamodb_table_name
  tags       = var.tags
}

module "sqs" {
  source = "./modules/sqs"

  queue_name        = var.sqs_queue_name
  max_receive_count = var.sqs_max_receive_count
  tags              = var.tags
}

###############################################################################
# 4. Cluster EKS (nodes em subnets publicas)
###############################################################################
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.networking.public_subnet_ids

  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  instance_type                = var.node_instance_type
  desired_size                 = var.node_desired_size
  min_size                     = var.node_min_size
  max_size                     = var.node_max_size
  disk_size                    = var.node_disk_size

  # Modo AWS Academy: passe a LabRole aqui para nao criar IAM
  existing_cluster_role_arn = var.existing_cluster_role_arn
  existing_node_role_arn    = var.existing_node_role_arn

  # Permissoes de aplicacao para pods (analytics-service) e KEDA scaler
  sqs_queue_arns      = [module.sqs.queue_arn, module.sqs.dlq_arn]
  dynamodb_table_arns = [module.dynamodb.table_arn]

  tags = var.tags
}

###############################################################################
# 5. Bancos relacionais e cache (subnets privadas)
###############################################################################
module "rds" {
  source = "./modules/rds"

  vpc_id            = module.networking.vpc_id
  identifier_prefix = var.project_name
  engine_version    = "16.15"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  username          = var.db_username

  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  skip_final_snapshot = true

  tags = var.tags
}

module "elasticache" {
  source = "./modules/elasticache"

  vpc_id            = module.networking.vpc_id
  identifier_prefix = "${var.project_name}-redis"
  node_type         = var.redis_node_type

  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  tags = var.tags
}

###############################################################################
# 6. CI - federacao OIDC do GitHub Actions
###############################################################################
module "github_oidc" {
  source = "./modules/github_oidc"

  project_name        = var.project_name
  github_repository   = var.github_repository
  ecr_repository_arns = module.ecr.repository_arns

  tags = var.tags
}

###############################################################################
# NOTA - ArgoCD:
# A instalacao do ArgoCD vive em uma CAMADA SEPARADA (terraform/argocd-install/)
# com estado proprio, pois exige o cluster ja criado e o kubeconfig gerado:
#   cd argocd-install && terraform init && terraform apply
###############################################################################
