variable "project_name" {
  description = "Nome do projeto."
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes (null = default do servico)."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets onde cluster e nodes serao criados."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint publico."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "Tipo de instancia dos nodes."
  type        = string
  default     = "t3.medium"
}

variable "desired_size" {
  description = "Nodes desejados."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Nodes minimos."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Nodes maximos."
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Disco raiz dos nodes (GB)."
  type        = number
  default     = 20
}

// --- Modo Academy/LabRole -----------------------------------------------------
variable "existing_cluster_role_arn" {
  description = "ARN de role existente p/ control plane (LabRole). Vazio = criar."
  type        = string
  default     = ""
}

variable "existing_node_role_arn" {
  description = "ARN de role existente p/ nodes (LabRole). Vazio = criar."
  type        = string
  default     = ""
}
// ------------------------------------------------------------------------------

variable "enable_cluster_oidc" {
  description = "Cria o OIDC provider do cluster (apenas quando modulo gerencia IAM)."
  type        = bool
  default     = true
}

variable "sqs_queue_arns" {
  description = "ARNs SQS que os pods/nodes podem consumir (analytics + KEDA)."
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arns" {
  description = "ARNs DynamoDB acessiveis pelos pods/nodes."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
