variable "project_name" {
  description = "Nome do projeto (prefixo da role)."
  type        = string
}

variable "github_repository" {
  description = "Repositorio autorizado (owner/repo)."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN de um provider OIDC GitHub JA EXISTENTE. Vazio = criar um novo."
  type        = string
  default     = ""
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositorios ECR que o CI pode acessar."
  type        = list(string)
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
