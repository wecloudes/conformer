# Transformation: aws-dynamodb-encryption — HARD enforcement for DynamoDB tables.
#
# Atomic, framework-agnostic, generic (any module). Forces server-side encryption
# on every aws_dynamodb_table. server_side_encryption is a NESTED block (not a
# flat attribute), so it is injected with asstring. Typed data source: an empty
# for_each (no matching resources) is a clean no-op.
#
# Control: CIS AWS Foundations / NIST 800-53 SC-28 (encryption at rest) for
# NoSQL table data.

data "resource" dynamodb {
  resource_type = "aws_dynamodb_table"
}

transform "update_in_place" dynamodb_encryption {
  for_each             = try(data.resource.dynamodb.result.aws_dynamodb_table, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    server_side_encryption {
      enabled = true
    }
  }
}
