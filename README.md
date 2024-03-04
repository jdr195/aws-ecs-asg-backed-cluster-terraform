# aws-ecs-asg-backed-cluster-terraform

Uses [Terraform](https://www.terraform.io/) to create the following

- VPC
- Internet Gateway
- Two public subnets
- Route table
- Route table Association
- Security Group with Ingress and Egress Rules
- EC2 Instance Profile
- Launch Template
- Autoscaling Group
- ECS Service Role (if it doesn't exist)
- ECS Capacity Provider
- ECS Cluster

This served mostly as a learning resource for me, but others may find some helpful tidbits as well.

### Example Usage

```
terraform init
terraform plan
terraform apply

# Cleanup
terraform destroy
```
