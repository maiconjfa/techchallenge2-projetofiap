output "db_identifiers" {
  description = "Identificadores das instancias RDS."
  value       = aws_db_instance.this[*].identifier
}

output "db_endpoints" {
  description = "Endpoints (host:porta) por banco."
  value       = { for db in aws_db_instance.this : db.db_name => db.address }
}

output "db_port" {
  description = "Porta de conexao."
  value       = aws_db_instance.this[0].port
}

output "db_username" {
  description = "Usuario master configurado."
  value       = var.username
}

output "db_passwords" {
  description = "Senhas geradas por banco (sensiveis - usar apenas para montar o Secret K8s)."
  value       = { for i, db in local.databases : db => random_password.this[i].result }
  sensitive   = true
}

output "security_group_id" {
  description = "SG compartilhado das instancias RDS."
  value       = aws_security_group.this.id
}
