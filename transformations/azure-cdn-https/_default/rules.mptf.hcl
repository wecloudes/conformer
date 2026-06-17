# Transformation: azure-cdn-https — force HTTPS-only delivery on CDN Endpoints.
# Azure equivalent of aws-cloudfront-https.
#
# Generic (any module). azurerm_cdn_endpoint with:
#   - is_http_allowed  = false  (disable plaintext HTTP; SOC2 CC6.7 / NIST SC-8 / PCI 4)
#   - is_https_allowed = true   (require HTTPS)
# Both are FLAT, in-place-updatable bools. Literal bools use asraw (verbatim).
# Empty for_each (no matching resource) = no-op.

data "resource" cdn {
  resource_type = "azurerm_cdn_endpoint"
}

transform "update_in_place" cdn_https {
  for_each             = try(data.resource.cdn.result.azurerm_cdn_endpoint, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    is_http_allowed  = false
    is_https_allowed = true
  }
}
