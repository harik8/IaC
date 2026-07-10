module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = local.vars.versions.cloudfront

  count = length(local.cloudfront_vars)

  aliases = local.cloudfront_vars[count.index]["aliases"]
  comment = try(local.cloudfront_vars[count.index]["comment"], "${terraform.workspace}-${local.cloudfront_vars[count.index]["name"]}")

  origin_access_control  = try(local.cloudfront_vars[count.index]["create_oac"], false) ? { "s3_${local.cloudfront_vars[count.index]["name"]}" = { origin_type = "s3", signing_behavior = "always", signing_protocol = "sigv4" } } : {}
  default_cache_behavior = local.cloudfront_vars[count.index]["default_cache_behavior"]
  default_root_object    = try(local.cloudfront_vars[count.index]["default_root_object"], "index.html")
  origin                 = local.cloudfront_vars[count.index]["origin"]
  ordered_cache_behavior = try(local.cloudfront_vars[count.index]["ordered_cache_behavior"], [])
  viewer_certificate     = try(local.cloudfront_vars[count.index]["viewer_certificate"], {})

  logging_config = try(local.cloudfront_vars[count.index]["logging_config"], null)
}

