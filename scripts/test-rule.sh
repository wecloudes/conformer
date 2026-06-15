#!/usr/bin/env bash
# Validate the current transformation units against a REAL upstream module,
# without the full stack. Runs inside the registry-api image (tofu/mapotf/jq on
# PATH) with the repo mounted at /repo. Driven by `make test-rule`.
#
#   test-rule.sh <framework> <namespace> <module> <provider> <version>
#   test-rule.sh cis_v600 terraform-aws-modules vpc aws 5.13.0
set -euo pipefail

FW="${1:?framework}"
NS="${2:?namespace}"
MOD="${3:?module}"
PROV="${4:?provider}"
VER="${5:?version}"
UPSTREAM="${UPSTREAM_REGISTRY:-registry.terraform.io}"

W="$(mktemp -d)"
cd "${W}"
cat > main.tf <<EOF
module "m" {
  source  = "${UPSTREAM}/${NS}/${MOD}/${PROV}"
  version = "${VER}"
}
EOF

echo "### tofu get ${UPSTREAM}/${NS}/${MOD}/${PROV} @ ${VER}"
tofu get >/dev/null
SRC="$(realpath "$(jq -r '.Modules[] | select(.Key=="m") | .Dir' .terraform/modules/modules.json)")"

echo "### applying ${FW} packs via patch-module.sh"
SKIP_VALIDATE=true /repo/scripts/patch-module.sh "${SRC}" /repo/patches "${FW}" "${MOD}" "${VER}" "${W}/out.zip" \
  | sed 's/^/  /'

mkdir -p "${W}/chk"
( cd "${W}/chk" && unzip -q "${W}/out.zip" )

echo "### compliance lines in patched module"
grep -rhnE "prevent_destroy|ignore_changes *=|traffic_type|enabled_cluster_log_types|storage_encrypted|deletion_protection|publicly_accessible|enable_telemetry|local_authentication_enabled|public_network_access_enabled" \
  "${W}/chk" 2>/dev/null | sed 's/^/  /' | sort -u | head -40 || echo "  (none matched)"

echo "### fmt check"
( cd "${W}/chk" && tofu fmt -check -recursive . >/dev/null 2>&1 && echo "  HCL formatted OK" || echo "  WARN: fmt would change something" )

rm -rf "${W}"
echo "### done"
