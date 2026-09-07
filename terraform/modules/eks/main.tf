###############################################################################
# Cluster EKS
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = local.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = false
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  # Garante que as policies estejam anexadas antes do cluster subir
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

###############################################################################
# Managed Node Group (subnets publicas - sem NAT, custo zero de egress lab)
###############################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-workers"
  node_role_arn   = local.node_role_arn

  subnet_ids     = var.subnet_ids
  capacity_type  = "ON_DEMAND"
  instance_types = [var.instance_type]
  disk_size      = var.disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "togglemaster"
  }

  depends_on = [
    aws_iam_role_policy.node_app_permissions,
    aws_eks_cluster.this,
  ]

  tags = merge(var.tags, {
    Name = "${var.project_name}-workers"
  })
}
