module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = local.vars.versions.eks

  create = local.vars.eks.create

  name                                     = terraform.workspace
  kubernetes_version                       = local.vars.eks.cluster_version
  endpoint_public_access                   = true
  create_kms_key                           = true
  enable_cluster_creator_admin_permissions = true
  control_plane_subnet_ids                 = module.vpc.private_subnets
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets

  access_entries = {
    aws_admin = {
      kubernetes_groups = []
      user_name         = "AWSEKSAdmin"
      principal_arn     = "arn:aws:iam::${var.account_id}:role/aws-reserved/sso.amazonaws.com/${var.aws_region}/AWSReservedSSO_AdministratorAccess_0ada0c673e6da443",

      policy_associations = {
        aws_eks_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = merge(
    {
      coredns = {
        most_recent = true
        configuration_values = jsonencode({
          computeType = "EC2"
          autoScaling = {
            enabled     = true
            minReplicas = 2
            maxReplicas = 2
          }
        })
      }
      kube-proxy = {
        most_recent = true
      }
      vpc-cni = {
        most_recent = true
      }
    },
    local.vars.efs.create ? {
      aws-efs-csi-driver = {
        most_recent              = true
        service_account_role_arn = "arn:aws:iam::${var.account_id}:role/${terraform.workspace}-efs-csi"
      }
    } : {}
  )
}

module "fargate_profile" {
  for_each = { for profile in local.vars.eks.fargate_profile : profile.name => profile }

  source  = "terraform-aws-modules/eks/aws//modules/fargate-profile"
  version = local.vars.versions.eks
  create  = local.vars.eks.create

  name         = "${module.eks.cluster_name}-${each.value.name}"
  cluster_name = module.eks.cluster_name

  subnet_ids = module.vpc.private_subnets
  selectors  = each.value.selectors
}

resource "aws_security_group_rule" "dns_tcp" {
  count = local.vars.eks.create ? 1 : 0

  description              = "Allow pods to communicate with the CoreDNS on Fargate"
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = module.eks.cluster_primary_security_group_id
}

resource "aws_security_group_rule" "dns_udp" {
  count = local.vars.eks.create ? 1 : 0

  description              = "Allow pods to communicate with the CoreDNS on Fargate"
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "udp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = module.eks.cluster_primary_security_group_id
}

resource "kubernetes_storage_class_v1" "gp3" {
  count = local.vars.eks.create && local.vars.eks.sc.gp3 ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = false

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

resource "kubernetes_storage_class_v1" "efs" {
  count = local.vars.eks.create && local.vars.eks.sc.efs ? 1 : 0

  metadata {
    name = "efs"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = module.efs.id
    directoryPerms   = "700"
  }

  reclaim_policy      = "Delete"
  volume_binding_mode = "Immediate"
}

# ── Self-managed node groups ──────────────────────────────────────────────────
# Self-managed nodes give full control over the launch template and ASG.
# SPOT is configured via instance_market_options instead of capacity_type.
# The module creates its own IAM role + instance profile and registers an
# access entry so nodes can join the cluster automatically.

# ── EKS managed node groups ───────────────────────────────────────────────────

module "eks_managed_node_group_application" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = local.vars.versions.eks

  create = local.vars.eks.create

  name                 = "${terraform.workspace}-application"
  cluster_name         = terraform.workspace
  kubernetes_version   = local.vars.eks.cluster_version
  cluster_service_cidr = module.eks.cluster_service_cidr

  subnet_ids = module.vpc.private_subnets

  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]

  ami_type = "AL2023_ARM_64_STANDARD"

  min_size     = 1
  max_size     = 1
  desired_size = 1

  instance_types = ["t4g.small"]
  capacity_type  = "SPOT"

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_type = "gp3"
        encrypted   = true
      }
    }
  }

  taints = {
    dedicated = {
      key    = "application"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

module "eks_managed_node_group_ingress_controller" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = local.vars.versions.eks

  create = local.vars.eks.create

  name                 = "${terraform.workspace}-ingress"
  cluster_name         = terraform.workspace
  kubernetes_version   = local.vars.eks.cluster_version
  cluster_service_cidr = module.eks.cluster_service_cidr

  subnet_ids = module.vpc.private_subnets

  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]

  ami_type = "AL2023_ARM_64_STANDARD"

  min_size     = 1
  max_size     = 1
  desired_size = 1

  instance_types = ["t4g.small"]
  capacity_type  = "SPOT"

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_type = "gp3"
        encrypted   = true
      }
    }
  }

  taints = {
    dedicated = {
      key    = "ingress-controller"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

module "eks_managed_node_group_core_addons" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = local.vars.versions.eks

  create = local.vars.eks.create

  name                 = "${terraform.workspace}-core-addons"
  cluster_name         = terraform.workspace
  kubernetes_version   = local.vars.eks.cluster_version
  cluster_service_cidr = module.eks.cluster_service_cidr

  subnet_ids = module.vpc.private_subnets

  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]

  ami_type = "AL2023_ARM_64_STANDARD"

  min_size     = 1
  max_size     = 1
  desired_size = 1

  instance_types = ["t4g.small"]
  capacity_type  = "SPOT"

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_type = "gp3"
        encrypted   = true
      }
    }
  }

  taints = {
    dedicated = {
      key    = "core-addons"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}


module "irsa_efs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = local.vars.versions.iam

  create = local.vars.eks.create && contains(keys(module.eks.cluster_addons), "aws-efs-csi-driver")

  name                  = "${terraform.workspace}-efs-csi"
  use_name_prefix       = false
  attach_efs_csi_policy = true

  oidc_providers = {
    efs = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}
