output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN da VPC."
  value       = aws_vpc.this.arn
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas (nodes EKS)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (RDS/ElastiCache)."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID da route table publica."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs das route tables privadas."
  value       = aws_route_table.private[*].id
}
