# output "eks" {
#   value = module.eks
# }

output "nlb_dns_name" {
  description = "NLB DNS name — create a CNAME record pointing to this"
  value       = local.vars.nlb.create ? module.nlb.dns_name : null
}

output "nlb_arn" {
  description = "NLB ARN"
  value       = local.vars.nlb.create ? module.nlb.arn : null
}
