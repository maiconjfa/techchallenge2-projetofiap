resource "aws_ecr_repository" "this" {
  count = length(var.repository_names)

  name                 = var.repository_names[count.index]
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  # Scan automatico de vulnerabilidades no push (basic scanning)
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = var.repository_names[count.index]
  })
}

# Mantem as N imagens mais recentes e descarta imagens sem tag.
# MUTABLE (e nao IMMUTABLE) permite re-execucao de pipelines que reenviam
# a mesma tag de commit hash em casos de retry.
resource "aws_ecr_lifecycle_policy" "this" {
  count = length(aws_ecr_repository.this)

  repository = aws_ecr_repository.this[count.index].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Descarta imagens sem tag"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = [{ type = "expire" }]
      },
      {
        rulePriority = 2
        description  = "Mantem as ${var.image_retention_count} ultimas imagens"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.image_retention_count
        }
        action = [{ type = "expire" }]
      }
    ]
  })
}
