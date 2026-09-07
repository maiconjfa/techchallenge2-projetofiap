###############################################################################
# ElastiCache Redis - cache do evaluation-service (hot path)
###############################################################################

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier_prefix}-sg"
  description = "Acesso Redis apenas a partir dos nodes EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis a partir dos nodes EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.identifier_prefix}-sg"
  })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.identifier_prefix}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier_prefix}-subnet-group"
  })
}

# Cluster single-node: suficiente para o lab; para HA use replication group.
resource "aws_elasticache_cluster" "this" {
  cluster_id           = var.identifier_prefix
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = var.parameter_group_name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  apply_immediately = true

  tags = merge(var.tags, {
    Name = var.identifier_prefix
  })
}
