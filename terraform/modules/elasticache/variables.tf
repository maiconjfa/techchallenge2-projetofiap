variable "vpc_id" {
  description = "ID da VPC."
  type        = string
}

variable "identifier_prefix" {
  description = "Identificador do cluster Redis (ex.: togglemaster-redis)."
  type        = string
}

variable "engine_version" {
  description = "Versao do engine Redis."
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "Tipo do node de cache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "parameter_group_name" {
  description = "Parameter group do Redis."
  type        = string
  default     = "default.redis7"
}

variable "subnet_ids" {
  description = "Subnets privadas para o subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups com acesso ao Redis (SG dos nodes EKS)."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
