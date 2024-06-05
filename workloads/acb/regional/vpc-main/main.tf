module "tag" {
  source = "github.com/harik8/tofu-modules//modules/tag?ref=main"

  description = var.tags.description
  utilization = var.tags.utilization
  workload    = var.tags.workload
  owner       = var.tags.owner
}

module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.8.1"

  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 4)]

  enable_nat_gateway = false

  private_subnet_tags      = local.private_subnet_tags
  public_subnet_tags       = local.public_subnet_tags
  private_route_table_tags = local.private_subnet_tags
  public_route_table_tags  = local.public_subnet_tags

  tags = module.tag.default_tags
}

#----------------#
#  NAT INSTANCE  #              
#----------------#     

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.main.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nat.id]
  source_dest_check           = false

  iam_instance_profile = aws_iam_instance_profile.nat.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y iptables-services
              sysctl -w net.ipv4.ip_forward=1
              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              service iptables save
              EOF

  tags = local.nat_instance_tags
}

resource "aws_iam_role" "nat" {
  name = local.nat_instance_tags["Name"]

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.nat_instance_tags
}

resource "aws_iam_role_policy_attachment" "nat" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  name = local.nat_instance_tags["Name"]
  role = aws_iam_role.nat.name
}

resource "aws_security_group" "nat" {
  name   = local.nat_instance_tags["Name"]
  vpc_id = module.vpc.vpc_id

  tags = local.nat_instance_tags
}

resource "aws_security_group_rule" "nat_ingress" {
  type              = "ingress"
  security_group_id = aws_security_group.nat.id
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

resource "aws_security_group_rule" "nat_egress" {
  type              = "egress"
  security_group_id = aws_security_group.nat.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

resource "aws_network_interface" "nat" {
  subnet_id         = module.vpc.public_subnets[0]
  security_groups   = [aws_security_group.nat.id]
  source_dest_check = false

  attachment {
    instance     = aws_instance.nat.id
    device_index = 1
  }
}

resource "aws_route" "nat" {
  count = length(module.vpc.private_route_table_ids)

  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.nat.id
}