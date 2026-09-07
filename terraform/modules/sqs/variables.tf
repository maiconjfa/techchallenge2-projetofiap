variable "queue_name" {
  description = "Nome da fila SQS principal."
  type        = string
}

variable "max_receive_count" {
  description = "Numero de recebimentos antes do redrive para a DLQ."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
