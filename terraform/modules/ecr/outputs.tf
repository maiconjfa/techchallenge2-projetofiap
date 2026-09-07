output "repository_arns" {
  description = "ARNs dos repositorios ECR."
  value       = aws_ecr_repository.this[*].arn
}

output "repository_urls" {
  description = "URLs dos repositorios ECR."
  value       = { for r in aws_ecr_repository.this : r.name => r.repository_url }
}
