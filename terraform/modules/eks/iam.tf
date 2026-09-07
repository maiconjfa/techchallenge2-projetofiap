###############################################################################
# Modo de operacao:
#   - Conta propria (default): cria roles IAM do cluster/nodes + OIDC provider
#   - AWS Academy: informe existing_cluster_role_arn / existing_node_role_arn
#     com a LabRole -> nada de IAM e criado, roles existentes sao reutilizadas
###############################################################################

locals {
  cluster_role_arn = var.existing_cluster_role_arn != "" ? var.existing_cluster_role_arn : aws_iam_role.cluster[0].arn
  node_role_arn    = var.existing_node_role_arn != "" ? var.existing_node_role_arn : aws_iam_role.node[0].arn

  create_iam = var.existing_cluster_role_arn == "" && var.existing_node_role_arn == ""
}

###############################################################################
# Roles (apenas em conta propria)
###############################################################################

data "aws_iam_policy_document" "cluster_assume" {
  count = local.create_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = local.create_iam ? 1 : 0

  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

data "aws_iam_policy_document" "node_assume" {
  count = local.create_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.create_iam ? 1 : 0

  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Permissoes de aplicacao usadas pelos pods via credenciais da instancia
# (analytics-service consumindo SQS/DynamoDB e KEDA escalando pela fila).
# Na Academy a LabRole ja possui permissoes amplas - politica nao aplicada.
resource "aws_iam_role_policy" "node_app_permissions" {
  count = local.create_iam ? 1 : 0

  name = "${var.project_name}-node-app-permissions"
  role = aws_iam_role.node[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsumerAndScaler"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_queue_arns
      },
      {
        Sid    = "DynamoDBAnalytics"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = var.dynamodb_table_arns
      }
    ]
  })
}

# OIDC provider do cluster (base para IRSA no futuro). Criado apenas quando
# o modulo gerencia o IAM; na Academy isso exigiria permissao inexistente.
resource "aws_iam_openid_connect_provider" "this" {
  count = local.create_iam && var.enable_cluster_oidc ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]

  tags = var.tags
}
