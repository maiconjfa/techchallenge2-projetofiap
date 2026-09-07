variable "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado por 'aws eks update-kubeconfig'."
  type        = string
  default     = "~/.kube/config"
}

variable "cluster_name" {
  description = "Nome/contexto do cluster EKS no kubeconfig."
  type        = string
  default     = "togglemaster-eks"
}
