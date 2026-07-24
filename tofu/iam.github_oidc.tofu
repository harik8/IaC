module "iam_github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = local.vars.versions.iam
}

module "iam_github_oidc_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = local.vars.versions.iam

  name            = "${terraform.workspace}-github-oidc-role"
  use_name_prefix = false

  enable_github_oidc     = true
  oidc_wildcard_subjects = local.vars.iam.github_oidc.repos
}

module "iam_github_hp_dev_s3_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = local.vars.versions.iam

  name        = "${terraform.workspace}-github-hp-dev-s3-policy"
  path        = "/"
  description = "IAM policy for GitHub OIDC role to access ${terraform.workspace}-hp-dev S3 bucket"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject*"
      ],
      "Effect": "Allow",
      "Resource": [
          "arn:aws:s3:::${terraform.workspace}-hp-dev/*"
        ]
    },
    {
      "Action": [
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
          "arn:aws:s3:::${terraform.workspace}-hp-dev"
        ]
    }
  ]
}
EOF
}

module "iam_assumable_role_github_hp_dev" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = local.vars.versions.iam

  name            = "${terraform.workspace}-github-hp-dev-role"
  use_name_prefix = false

  trust_policy_permissions = {
    AllowAssumeRole = {
      actions = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      principals = [{
        type        = "AWS"
        identifiers = [module.iam_github_oidc_role.arn]
      }]
    }
  }

  policies = {
    github_hp_dev_s3 = module.iam_github_hp_dev_s3_policy.arn
  }
}

module "iam_assumable_role_github_awsing" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = local.vars.versions.iam

  name            = "${terraform.workspace}-github-awsing-role"
  use_name_prefix = false

  trust_policy_permissions = {
    AllowAssumeRole = {
      actions = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      principals = [{
        type = "AWS"
        identifiers = [
          module.iam_github_oidc_role.arn,
          "arn:aws:iam::${var.account_id}:role/${terraform.workspace}-github-awsing-role",
          "arn:aws:sts::${var.account_id}:assumed-role/AWSReservedSSO_AdministratorAccess_0ada0c673e6da443/hari.karthigasu"
        ]
      }]
    }
  }

  # policies = {
  #   AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  # }
}

