output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  value = [for k in sort(keys(aws_subnet.public)) : aws_subnet.public[k].id]
}

output "private_subnet_ids" {
  value = [for k in sort(keys(aws_subnet.private)) : aws_subnet.private[k].id]
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}
