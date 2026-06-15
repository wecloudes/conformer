# HARD enforcement for terraform-aws-eks.
#
# aws_eks_cluster.this is at the module root. Force the full control-plane audit
# log set (CIS EKS) regardless of var.cluster_enabled_log_types. The _default
# aws-modules pack also flips cluster_endpoint_public_access to false (soft).

data "resource" eks {
  resource_type = "aws_eks_cluster"
}

transform "update_in_place" eks_audit_logs {
  for_each             = try(data.resource.eks.result.aws_eks_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  }
}
