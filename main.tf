terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.39.0"
    }
  }
  required_version = ">= 1.7.4"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(
    var.tags,
    {
      Name = "Terraform"
    },
  )
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "Terraform"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names[*], count.index)
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "Terraform Public Subnet ${count.index + 1}"
    }
  )
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(
    var.tags,
    {
      Name = "Terraform Public Route Table"
    }
  )
}

resource "aws_route_table_association" "public_subnet_route_table_assocation" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "ecs-instances" {
  name        = "ecs-instances"
  description = "Allows traffic to container ports on ECS Instances"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "ecs-instances"
  }
}

resource "aws_vpc_security_group_ingress_rule" "container-ports" {
  security_group_id = aws_security_group.ecs-instances.id
  from_port         = 32768
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = aws_vpc.main.cidr_block
  description       = "Container Ports to VPC CIDR"
}

resource "aws_vpc_security_group_egress_rule" "outbound-to-all" {
  security_group_id = aws_security_group.ecs-instances.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All Outbound Ipv4"
}

resource "aws_iam_role" "ecsInstanceRole" {
  name               = "ecsInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "container_service_policy_attachments" {
  count      = length(var.instance_role_policies)
  role       = aws_iam_role.ecsInstanceRole.name
  policy_arn = element(var.instance_role_policies, count.index)
}

resource "aws_iam_instance_profile" "ecsInstanceProfile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecsInstanceRole.name
}

resource "aws_launch_template" "ecs-launch-template" {
  name                   = "ecs"
  vpc_security_group_ids = [aws_security_group.ecs-instances.id]
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = "t3.small"
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      encrypted = true
      volume_size = 50
      volume_type = "gp3"
    }
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.ecsInstanceProfile.arn
  }
  monitoring {
    enabled = false
  }
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    instance_metadata_tags = "enabled"

  }
  ebs_optimized = true
  user_data = base64encode(
    templatefile(
      "userdata.sh.tftpl",
      { cluster_name = var.ecs_cluster_name }
    )
  )
  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

}

resource "aws_autoscaling_group" "asg" {
  min_size = 1
  max_size = 1
  desired_capacity = 1
  name = var.ecs_cluster_name
  force_delete = true
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  launch_template {
    id = aws_launch_template.ecs-launch-template.id
    version = "$Latest"
  }
  protect_from_scale_in = true
  termination_policies = ["OldestInstance"]
  tag {
    key = "AmazonECSManaged"
    value = true
    propagate_at_launch = true
  }
}

resource "aws_iam_service_linked_role" "ecs" {
  count = local.role_exists ? 0 : 1
  aws_service_name = "ecs.amazonaws.com"
}

resource "aws_ecs_capacity_provider" "capacity_provider" {
  name = var.ecs_cluster_name
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.asg.arn
    managed_termination_protection = "ENABLED"
    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status = "ENABLED"
      target_capacity = 95
    }
    managed_draining = "ENABLED"
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = var.ecs_cluster_name
  setting {
    name = "containerInsights"
    value = "enabled"
  }
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "capacity_provider_association" {
  cluster_name = var.ecs_cluster_name
  capacity_providers = [aws_ecs_cluster.cluster.name]
  default_capacity_provider_strategy {
    base = 1
    weight = 100
    capacity_provider = aws_ecs_cluster.cluster.name
  }
  depends_on = [ aws_ecs_capacity_provider.capacity_provider ]
}