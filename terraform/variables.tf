###############################################################################
# Variaveis globais
###############################################################################

variable "aws_region" {
  description = "Regiao AWS onde a infraestrutura sera provisionada."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo de recursos."
  type        = string
  default     = "togglemaster"
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "togglemaster-eks"
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos."
  type        = map(string)
  default     = {}
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR da VPC dedicada ao ToggleMaster."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs usadas para as subnets publicas e privadas."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (nodes EKS)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (RDS e ElastiCache)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

###############################################################################
# EKS
###############################################################################

# --- Modo AWS Academy / LabRole ---------------------------------------------
# Na AWS Academy nao se cria IAM: informe os ARNs abaixo com a LabRole e o
# modulo passa a reutiliza-los em vez de criar roles novas.
variable "existing_cluster_role_arn" {
  description = "ARN de role EXISTENTE para o control plane (ex.: LabRole na Academy). Vazio = criar role nova."
  type        = string
  default     = ""
}

variable "existing_node_role_arn" {
  description = "ARN de role EXISTENTE para os nodes (ex.: LabRole na Academy). Vazio = criar role nova."
  type        = string
  default     = ""
}
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Versao do Kubernetes do cluster EKS (null = versao default do servico)."
  type        = string
  default     = null
}

variable "node_instance_type" {
  description = "Tipo de instancia dos nodes do EKS."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade minima de nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Quantidade maxima de nodes."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco raiz dos nodes (GB)."
  type        = number
  default     = 20
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs com acesso ao endpoint publico do cluster."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# Bancos de dados
###############################################################################

variable "db_username" {
  description = "Usuario master das instancias RDS PostgreSQL."
  type        = string
  default     = "toggleadmin"
}

variable "db_instance_class" {
  description = "Classe das instancias RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento inicial (GB) de cada instancia RDS."
  type        = number
  default     = 20
}

variable "redis_node_type" {
  description = "Tipo do node ElastiCache Redis."
  type        = string
  default     = "cache.t4g.micro"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de analitica."
  type        = string
  default     = "ToggleMasterAnalytics"
}

###############################################################################
# Mensageria
###############################################################################

variable "sqs_queue_name" {
  description = "Nome da fila SQS de eventos de avaliacao."
  type        = string
  default     = "tooglemaster-evaluation-events-queue"
}

variable "sqs_max_receive_count" {
  description = "Tentativas antes de enviar a mensagem para a DLQ."
  type        = number
  default     = 5
}

###############################################################################
# Repositorios ECR
###############################################################################

variable "ecr_repository_names" {
  description = "Repositorios ECR dos microsservicos."
  type        = list(string)
  default = [
    "togglemaster-auth",
    "togglemaster-flag",
    "togglemaster-targeting",
    "togglemaster-evaluation",
    "togglemaster-analytics",
  ]
}

variable "ecr_image_retention_count" {
  description = "Quantidade de imagens mantidas por repositorio ECR."
  type        = number
  default     = 10
}

###############################################################################
# GitHub OIDC (CI)
###############################################################################

variable "github_repository" {
  description = "Repositorio GitHub autorizado a assumir a role de CI (formato owner/repo)."
  type        = string
  default     = "maiconjfa/techchallenge2-projetofiap"
}

###############################################################################
# ArgoCD
###############################################################################
# A instalacao do ArgoCD fica na camada terraform/argocd-install/ (estado
# proprio) e roda apos o primeiro apply, com o kubeconfig ja gerado.
