variable "tags" {
  default = {
    Application = "Terraform-ECS"
  }
}

variable "ecs_cluster_name" {
  type = string
  default = "my_ecs_cluster"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDR Values"
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "instance_role_policies" {
  type        = list(string)
  description = "List of managed policies to attach to the ECS Instance Role"
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

data "aws_iam_roles" "role" {
  name_regex = "AWSServiceRoleForECS"
}

locals {
  role_exists = can(data.aws_iam_roles.role.arns)
}
