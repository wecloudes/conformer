# Transformation: aws-apigateway-harden — enable X-Ray tracing on API Gateway.
#
# Generic (any module). aws_api_gateway_stage with xray_tracing_enabled = true
# (AWS Config: api-gw-xray-enabled; SOC2 CC7.2 / NIST AU-2 monitoring &
# traceability of API calls). Flat bool — asraw (verbatim literal). Empty
# for_each = no-op.

data "resource" agw {
  resource_type = "aws_api_gateway_stage"
}

transform "update_in_place" apigw_xray {
  for_each             = try(data.resource.agw.result.aws_api_gateway_stage, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    xray_tracing_enabled = true
  }
}
