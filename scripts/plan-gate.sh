#!/usr/bin/env bash
# Plan-time compliance gate (DIY playbook slide 29, layer 2).
#
# Runs `terraform show -json` over a saved plan and uses jq to assert that the
# resources the consumer is about to create actually satisfy the controls the
# source-time transforms cannot guarantee (caller-supplied values resolve only
# at plan time). Exits non-zero on any violation -> turns CI red.
#
#   terraform plan -out tfplan
#   ./scripts/plan-gate.sh tfplan
set -euo pipefail

PLAN_FILE="${1:-tfplan}"
[ -f "${PLAN_FILE}" ] || { echo "usage: plan-gate.sh <planfile>"; exit 2; }

JSON="$(terraform show -json "${PLAN_FILE}")"
fail=0

check() {
  local label="$1" filter="$2"
  if echo "${JSON}" | jq -e "${filter}" >/dev/null; then
    echo "  PASS  ${label}"
  else
    echo "  FAIL  ${label}"
    fail=1
  fi
}

echo "=== plan-gate: ${PLAN_FILE} ==="

# Every public access block must lock all four flags.
check "public access fully blocked" '
  [ .resource_changes[]
    | select(.type=="aws_s3_bucket_public_access_block")
    | select(.change.after.block_public_acls != true
          or .change.after.block_public_policy != true
          or .change.after.ignore_public_acls != true
          or .change.after.restrict_public_buckets != true)
  ] | length == 0'

# Every bucket being created must also create an SSE configuration.
check "encryption configured for each bucket" '
  ([ .resource_changes[] | select(.type=="aws_s3_bucket") ] | length)
  <= ([ .resource_changes[] | select(.type=="aws_s3_bucket_server_side_encryption_configuration") ] | length)'

# No bucket may be left without versioning.
check "versioning configured for each bucket" '
  ([ .resource_changes[] | select(.type=="aws_s3_bucket") ] | length)
  <= ([ .resource_changes[] | select(.type=="aws_s3_bucket_versioning") ] | length)'

if [ "${fail}" -ne 0 ]; then
  echo "=== plan-gate: VIOLATIONS FOUND ==="
  exit 1
fi
echo "=== plan-gate: all controls satisfied ==="
