variable "repository_names" {
  description = "Lista de repositorios ECR a serem criados."
  type        = list(string)
}

variable "image_retention_count" {
  description = "Quantidade de imagens mantidas por repositorio."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
