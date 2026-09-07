###############################################################################
# Outputs - insumos para o GitOps (gitops/) e para o runbook do README
#
# Apos o apply, gere o Secret Kubernetes com:
#   cd terraform && ./scripts/generate-k8s-secrets.sh
###############################################################################

# --- Networking --------------------------------------------------------------
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

# --- EKS -----------------------------------------------------------------------
output "eks_cluster_name" {
  value = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  value = module.eks.cluster_version_actual
}

output "kubectl_config_command" {
  description = "Comando para configurar o acesso local ao cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_id} --region ${var.aws_region}"
}

# --- RDS ----------------------------------------------------------------------
output "rds_endpoints" {
  description = "Endpoint de cada banco PostgreSQL (auth_db, flag_db, targeting_db)."
  value       = module.rds.db_endpoints
}

output "rds_username" {
  value = module.rds.db_username
}

output "rds_passwords" {
  value     = module.rds.db_passwords
  sensitive = true
}

# --- ElastiCache ----------------------------------------------------------------
output "redis_url" {
  value = module.elasticache.redis_url
}

# --- SQS --------------------------------------------------------------------------
output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "sqs_queue_arn" {
  value = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  value = module.sqs.dlq_url
}

# --- DynamoDB ------------------------------------------------------------------------
output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  value = module.dynamodb.table_arn
}

# --- ECR ------------------------------------------------------------------------------
output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR por microsservico."
  value       = module.ecr.repository_urls
}

# --- CI (GitHub OIDC) --------------------------------------------------------------------
output "github_ci_role_arn" {
  description = "Configure este ARN no secret AWS_ROLE do GitHub Actions."
  value       = module.github_oidc.role_arn
}
