output "role_arn" {
  description = "ARN da role assumida pelo GitHub Actions (usar como aws-role no CI)."
  value       = aws_iam_role.ci.arn
}
