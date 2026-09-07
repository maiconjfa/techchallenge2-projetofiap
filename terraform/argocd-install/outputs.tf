output "argocd_namespace" {
  description = "Namespace onde o ArgoCD esta instalado."
  value       = module.argocd.namespace
}

output "ui_access_command" {
  description = "Comando para acessar a UI do ArgoCD."
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "initial_admin_password_command" {
  description = "Comando para obter a senha inicial do admin."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
