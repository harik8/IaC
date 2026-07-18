resource "aws_security_group" "nlb" {
  count = local.vars.nlb.create ? 1 : 0

  name_prefix = "${terraform.workspace}-nlb-"
  description = "NLB fronting EKS ingress-controller nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS/TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vars.vpc.cidr]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow the NLB to reach port 80 on the ingress-controller nodes.
resource "aws_security_group_rule" "nodes_allow_nlb_http" {
  count = local.vars.nlb.create ? 1 : 0

  description              = "Allow NLB to reach port 80 on ingress-controller nodes"
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = aws_security_group.nlb[0].id
}

# NLB health check probes originate from the NLB node's private IP, not from
# the NLB security group — so source_security_group_id does not work here.
# Allow port 1042 from the VPC CIDR so health checks can reach HAProxy.
resource "aws_security_group_rule" "nodes_allow_nlb_healthcheck" {
  count = local.vars.nlb.create ? 1 : 0

  description       = "Allow NLB health checks on port 1042 from VPC"
  type              = "ingress"
  from_port         = 1042
  to_port           = 1042
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [local.vars.vpc.cidr]
}

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = local.vars.versions.alb

  create = local.vars.nlb.create

  name               = "${terraform.workspace}-public"
  load_balancer_type = "network"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = local.vars.nlb.create ? [aws_security_group.nlb[0].id] : []
  internal           = local.vars.nlb.internal

  enable_cross_zone_load_balancing = true

  target_groups = {
    http = {
      name                 = "${terraform.workspace}-http"
      protocol             = "TCP"
      port                 = 80
      target_type          = "instance"
      vpc_id               = module.vpc.vpc_id
      deregistration_delay = 30

      # Targets are managed by aws_autoscaling_attachment below —
      # do not let the module register static targets.
      create_attachment = false

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 2
        interval            = 10
        protocol            = "HTTP"
        port                = "1042"
        path                = "/healthz"
        success_codes       = "200-299"
      }
    }
  }

  listeners = {
    tcp_80 = {
      port     = 80
      protocol = "TCP"

      forward = {
        target_group_key = "http"
      }
    }

    tls_443 = {
      port            = 443
      protocol        = "TLS"
      certificate_arn = "arn:aws:acm:${var.aws_region}:${var.account_id}:certificate/e3edb543-521e-4592-a9aa-4b817dc2c2e9"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

      forward = {
        target_group_key = "http"
      }
    }
  }
}

resource "aws_autoscaling_attachment" "ingress_to_nlb" {
  count = local.vars.nlb.create ? 1 : 0

  autoscaling_group_name = module.eks_managed_node_group_ingress_controller.node_group_resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = module.nlb.target_groups["http"].arn
}
