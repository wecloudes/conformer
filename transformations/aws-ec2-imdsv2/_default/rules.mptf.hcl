# Transformation: aws-ec2-imdsv2 — require IMDSv2 on EC2 instances and launch
# templates.
#
# Generic (any module). CIS AWS Foundations 5.6: "Ensure that EC2 Metadata
# Service only allows IMDSv2." IMDSv2 is enforced by setting http_tokens =
# "required" inside the metadata_options block. We use asraw (NOT asstring): the
# value is a STRING literal, and asstring evaluates the RHS — it would emit
# `http_tokens = required` (unquoted, invalid HCL). asraw writes the nested block
# verbatim, preserving the quotes. Empty for_each (no matching resource) = no-op.

data "resource" ec2_instance {
  resource_type = "aws_instance"
}

data "resource" ec2_launch_template {
  resource_type = "aws_launch_template"
}

transform "update_in_place" instance_imdsv2 {
  for_each             = try(data.resource.ec2_instance.result.aws_instance, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    metadata_options {
      http_tokens = "required"
    }
  }
}

transform "update_in_place" launch_template_imdsv2 {
  for_each             = try(data.resource.ec2_launch_template.result.aws_launch_template, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    metadata_options {
      http_tokens = "required"
    }
  }
}
