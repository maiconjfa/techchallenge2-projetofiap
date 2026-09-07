variable "table_name" {
  description = "Nome da tabela DynamoDB."
  type        = string
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
