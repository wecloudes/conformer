# Transformation: aws-msk-encryption — force TLS in transit on MSK (Kafka).
#
# Generic (any module). aws_msk_cluster with encryption_info.encryption_in_transit
# .client_broker = "TLS" (AWS Config: msk-in-cluster-node-require-tls; SOC2 CC6.7
# / NIST SC-8 / PCI 4 — encryption in transit). Doubly-NESTED block with a STRING
# value, so this uses asraw (writes the nested blocks verbatim, keeping quotes;
# asstring would emit `client_broker = TLS`, invalid HCL). Empty for_each = no-op.

data "resource" msk {
  resource_type = "aws_msk_cluster"
}

transform "update_in_place" msk_tls_in_transit {
  for_each             = try(data.resource.msk.result.aws_msk_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    encryption_info {
      encryption_in_transit {
        client_broker = "TLS"
      }
    }
  }
}
