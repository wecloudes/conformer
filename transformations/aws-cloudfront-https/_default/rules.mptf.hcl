# Transformation: aws-cloudfront-https — force HTTPS + modern TLS on CloudFront.
#
# Generic (any module). aws_cloudfront_distribution:
#   - default_cache_behavior.viewer_protocol_policy = "redirect-to-https"
#     (AWS Config: cloudfront-viewer-policy-https; SOC2 CC6.7 / NIST SC-8 / PCI 4)
#   - viewer_certificate.minimum_protocol_version = "TLSv1.2_2021"
# Both are NESTED blocks holding STRING values, so this uses asraw — it writes
# the block verbatim, KEEPING the quotes. (asstring would evaluate the string and
# emit it unquoted = invalid HCL.) Empty for_each = no-op.

data "resource" cf {
  resource_type = "aws_cloudfront_distribution"
}

transform "update_in_place" cloudfront_viewer_https {
  for_each             = try(data.resource.cf.result.aws_cloudfront_distribution, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    default_cache_behavior {
      viewer_protocol_policy = "redirect-to-https"
    }
  }
}

transform "update_in_place" cloudfront_min_tls {
  for_each             = try(data.resource.cf.result.aws_cloudfront_distribution, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    viewer_certificate {
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }
}
