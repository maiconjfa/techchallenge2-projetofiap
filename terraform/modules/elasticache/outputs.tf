output "endpoint_address" {
  description = "Endpoint do node Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "endpoint_port" {
  description = "Porta do node Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "redis_url" {
  description = "URL de conexao pronta para as aplicacoes."
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.cache_nodes[0].port}"
}
