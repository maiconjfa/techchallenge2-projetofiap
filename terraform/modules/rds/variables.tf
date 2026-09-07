variable "vpc_id" {
  description = "ID da VPC onde as instancias serao criadas."
  type        = string
}

variable "identifier_prefix" {
  description = "Prefixo dos identificadores das instancias (ex.: togglemaster-auth-db)."
  type        = string
}

variable "engine_version" {
  description = "Versao major do PostgreSQL."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Classe das instancias RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial em GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite de auto-scaling de armazenamento em GB."
  type        = number
  default     = 50
}

variable "username" {
  description = "Usuario master."
  type        = string
  default     = "toggleadmin"
}

variable "subnet_ids" {
  description = "Subnets privadas para o DB subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups com acesso as instancias (SG dos nodes EKS)."
  type        = list(string)
}

variable "backup_retention_period" {
  description = "Retencao de backup automatico (dias)."
  type        = number
  default     = 1
}

variable "skip_final_snapshot" {
  description = "Pula snapshot final na destruicao (true recomendado em lab)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
