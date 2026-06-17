# Transformation: aws-sqs-encryption — enable SSE-SQS encryption at rest on SQS
# queues.
#
# Generic (any module). Enforces encryption at rest for Amazon SQS using the
# SQS-managed server-side encryption key (SSE-SQS) by setting
# sqs_managed_sse_enabled = true. That argument is FLAT (a top-level resource
# attribute), so this uses asraw. Empty for_each (no matching resource) is a
# no-op.

data "resource" sqs_queue {
  resource_type = "aws_sqs_queue"
}

transform "update_in_place" sqs_encryption {
  for_each             = try(data.resource.sqs_queue.result.aws_sqs_queue, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    sqs_managed_sse_enabled = true
  }
}
