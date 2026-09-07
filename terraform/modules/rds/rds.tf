###############################################################################
# Recursos RDS (continuacao de main.tf - senhas, SG, subnet group, instancias)
###############################################################################

resource "random_password" "this" {
  count = length(local.databases)

  length           = 24
  special          = false
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier_prefix}-sg"
  description = "Acesso PostgreSQL apenas a partir dos nodes EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL a partir dos nodes EKS"
    from_port       = 5432
    to_port         = 5432
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

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier_prefix}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier_prefix}-subnet-group"
  })
}

resource "aws_db_instance" "this" {
  count = length(local.databases)

  identifier     = "${var.identifier_prefix}-${replace(local.databases[count.index], "_", "-")}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = local.databases[count.index]
  username = var.username
  password = random_password.this[count.index].result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.backup_retention_period
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.identifier_prefix}-${local.databases[count.index]}-final"
  delete_automated_backups   = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(var.tags, {
    Name    = "${var.identifier_prefix}-${local.databases[count.index]}"
    Service = local.databases[count.index]
  })
}
