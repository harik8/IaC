resource "aws_security_group" "nlb" {
  name   = local.nlb_public_tags["Name"]
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc["vpc_id"]

  tags = local.nlb_public_tags
}

resource "aws_security_group_rule" "nlb_ingress_443" {
  type              = "ingress"
  security_group_id = aws_security_group.nlb.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
}

resource "aws_security_group_rule" "nlb_egress" {
  type              = "egress"
  security_group_id = aws_security_group.nlb.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

resource "aws_security_group" "ecs" {
  name   = "${local.nlb_public_tags["Name"]}-ecs"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc["vpc_id"]

  tags = local.nlb_public_tags
}

resource "aws_security_group_rule" "ecs_allow_vpc" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  cidr_blocks       = ["10.0.0.0/16"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

resource "aws_security_group_rule" "ecs_egress" {
  type              = "egress"
  security_group_id = aws_security_group.ecs.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
}

# resource "aws_security_group_rule" "nlb_egress" {
#   type              = "egress"
#   security_group_id = aws_security_group.nlb.id
#   cidr_blocks       = ["0.0.0.0/0"]
#   from_port         = 0
#   to_port           = 0
#   protocol          = "-1"
# }

# resource "aws_security_group_rule" "allow_nlb_traffic" {
#   type                     = "ingress"
#   from_port                = 80
#   to_port                  = 80
#   protocol                 = "tcp"
#   security_group_id        = module.eks.cluster_security_group_id
#   source_security_group_id = aws_security_group.nlb.id
# }