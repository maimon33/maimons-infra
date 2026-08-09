locals {
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "aws_vpc" "platform" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  availability_zone               = var.availability_zone
  cidr_block                      = var.subnet_cidr
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.platform.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false
  vpc_id                          = aws_vpc.platform.id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform.id
  }

  route {
    gateway_id      = aws_internet_gateway.platform.id
    ipv6_cidr_block = "::/0"
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public"
  })
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_security_group" "host" {
  description = "Shared EC2 host; direct ingress is restricted to Cloudflare"
  name        = "${var.name_prefix}-host"
  vpc_id      = aws_vpc.platform.id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-host"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudflare_http_ipv4" {
  for_each = var.cloudflare_ipv4_cidrs

  cidr_ipv4         = each.value
  description       = "HTTP from Cloudflare"
  from_port         = 80
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.host.id
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "cloudflare_http_ipv6" {
  for_each = var.cloudflare_ipv6_cidrs

  cidr_ipv6         = each.value
  description       = "HTTP from Cloudflare"
  from_port         = 80
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.host.id
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.ssh_ipv4_cidrs

  cidr_ipv4         = each.value
  description       = "Temporary operator SSH; prefer SSM Session Manager"
  from_port         = 22
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.host.id
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Host outbound IPv4"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.host.id
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  cidr_ipv6         = "::/0"
  description       = "Host outbound IPv6"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.host.id
}
