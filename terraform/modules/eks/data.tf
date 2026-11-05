
data "aws_eks_cluster" "this" {
  count = 1
  name  = aws_eks_cluster.this.name
}
