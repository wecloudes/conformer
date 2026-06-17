# Transformation: aws-alb-harden — drop invalid HTTP headers on Application LBs.
#
# Generic (any module). aws_lb with drop_invalid_header_fields = true mitigates
# HTTP desync / header-smuggling (AWS Config: alb-http-drop-invalid-header-
# enabled; maps to SOC2 CC6.6 / NIST SC-8 transport integrity). Flat bool — use
# asraw (verbatim literal, no expression evaluation). Empty for_each = no-op.

data "resource" alb {
  resource_type = "aws_lb"
}

transform "update_in_place" alb_drop_invalid_headers {
  for_each             = try(data.resource.alb.result.aws_lb, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    drop_invalid_header_fields = true
  }
}
