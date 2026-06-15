# SOC 2 Type II — S3 Bucket structural transforms (mapotf)
#
# Mapped to Trust Services Criteria. CC6.1 access control + CC8.1 change
# management (versioning) + A1.2 availability (replication advisory).

variable "prevent_destroy" {
  type    = bool
  default = true
}

data "resource" bucket {
  resource_type = "aws_s3_bucket"
}

data "resource" pab {
  resource_type = "aws_s3_bucket_public_access_block"
}

# CC8.1 change management — protect against destroy (slide 27).
transform "update_in_place" soc2_prevent_destroy {
  for_each             = try(data.resource.bucket.result.aws_s3_bucket, {})
  target_block_address = each.value.mptf.block_address

  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}

# CC6.1 logical access — lock public access (slide 29).
transform "update_in_place" soc2_block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address

  asraw {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets  = true
  }
}

# CC6.1 / CC6.7 / CC7.2 / A1.2 plan-time assertions.
transform "new_block" soc2_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_soc2.tf"
  labels         = ["soc2_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[SOC2 CC6.1] encryption at rest must be configured."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[SOC2 CC6.7] non-TLS transport must be denied."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[SOC2 CC7.2] access logging must be enabled for monitoring."
    }
    assert {
      condition     = length(keys(var.replication_configuration)) > 0
      error_message = "[SOC2 A1.2 Advisory] consider cross-region replication for availability."
    }
  }
}
