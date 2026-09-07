output "cluster_id" {
  description = "ID/nome do cluster EKS."
  value       = aws_eks_cluster.this.id
}

output "cluster_endpoint" {
  description = "Endpoint do API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "CA do cluster (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version_actual" {
  description = "Versao efetiva do Kubernetes."
  value       = aws_eks_cluster.this.version
}

# Em managed node groups sem launch template proprio, as ENIs dos nodes
# recebem o security group primario do cluster. Liberar portas nesse SG
# equivale a liberar acesso para os nodes/pods.
output "node_security_group_id" {
  description = "SG compartilhado pelo control plane e pelos nodes (usar p/ acesso a RDS/Redis)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "ARN da role dos nodes (pods usam essas permissoes via pod identity)."
  value       = local.node_role_arn
}

output "cluster_role_arn" {
  description = "ARN da role do control plane."
  value       = local.cluster_role_arn
}

output "oidc_provider_arn" {
  description = "ARN do provider OIDC do cluster (vazio quando reutiliza roles existentes)."
  value       = var.existing_cluster_role_arn == "" ? try(aws_iam_openid_connect_provider.this[0].arn, "") : ""
}
