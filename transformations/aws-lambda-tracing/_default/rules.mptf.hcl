# Transformation: aws-lambda-tracing — enable active X-Ray tracing on Lambda.
#
# Generic (any module). aws_lambda_function with tracing_config.mode = "Active"
# (AWS Config: lambda-function-settings-check / observability; SOC2 CC7.2 /
# NIST AU-2 audit + traceability). tracing_config is a NESTED block holding a
# STRING value, so this uses asraw (writes verbatim, keeps the quotes — asstring
# would emit `mode = Active`, invalid HCL). Empty for_each = no-op.

data "resource" lambda {
  resource_type = "aws_lambda_function"
}

transform "update_in_place" lambda_xray {
  for_each             = try(data.resource.lambda.result.aws_lambda_function, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    tracing_config {
      mode = "Active"
    }
  }
}
