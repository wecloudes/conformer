#!/usr/bin/env bash
# Plan-time compliance gate (DIY playbook slide 29, layer 2).
#
# Runs `terraform show -json` over a saved plan and uses jq to assert that the
# resources the consumer is about to create actually satisfy the controls the
# source-time transforms CANNOT guarantee. Two reasons a control lands here
# instead of in a transformation unit:
#   1. caller-supplied values resolve only at plan time (S3 SSE / versioning), or
#   2. the control targets an INTERNAL module resource (ALB listener, WAF
#      association, API Gateway stage) whose attributes a generic source-time
#      force can't reach and whose module variables we don't know — but the plan
#      does. These are the "not flat-forceable" edge/transit controls.
#
# Exits non-zero on any violation -> turns CI red.
#
#   terraform plan -out tfplan
#   ./scripts/plan-gate.sh tfplan [framework]
#   ./scripts/plan-gate.sh --self-test        # no terraform needed
#
# framework (optional) only changes the clause IDs printed in each label; the
# assertions are identical across frameworks. Known: cis_v600 iso27001 soc2
# pci_dss hipaa nist_800_53 fedramp gdpr nis2 (default: generic AWS Config id).
set -euo pipefail

FW="${2:-generic}"

# Real clause per (control, framework). nist_800_53 and fedramp share NIST ids.
cite() {
  case "$1:${FW}" in
    elb:pci_dss) echo "PCI DSS 4.2.1" ;;
    elb:hipaa) echo "HIPAA §164.312(e)(1)" ;;
    elb:soc2) echo "SOC2 CC6.7" ;;
    elb:iso27001) echo "ISO 27001 A.8.24" ;;
    elb:nist_800_53|elb:fedramp) echo "NIST SC-8" ;;
    elb:gdpr) echo "GDPR Art.32(1)(a)" ;;
    elb:nis2) echo "NIS2 Art.21(2)(h)" ;;
    elb:cis_v600) echo "CIS AWS 4.x" ;;
    elb:*) echo "AWS Config elb-tls-listener" ;;

    waf:pci_dss) echo "PCI DSS 6.4.2" ;;
    waf:hipaa) echo "HIPAA §164.312(c)(1)" ;;
    waf:soc2) echo "SOC2 CC6.6" ;;
    waf:iso27001) echo "ISO 27001 A.8.23" ;;
    waf:nist_800_53|waf:fedramp) echo "NIST SC-7" ;;
    waf:gdpr) echo "GDPR Art.32(1)(b)" ;;
    waf:nis2) echo "NIS2 Art.21(2)(e)" ;;
    waf:cis_v600) echo "CIS AWS 4.x" ;;
    waf:*) echo "AWS Config waf-associated" ;;

    apigw:pci_dss) echo "PCI DSS 10.2.1" ;;
    apigw:hipaa) echo "HIPAA §164.312(b)" ;;
    apigw:soc2) echo "SOC2 CC7.2" ;;
    apigw:iso27001) echo "ISO 27001 A.8.15" ;;
    apigw:nist_800_53|apigw:fedramp) echo "NIST AU-2" ;;
    apigw:gdpr) echo "GDPR Art.30" ;;
    apigw:nis2) echo "NIS2 Art.21(2)(i)" ;;
    apigw:cis_v600) echo "CIS AWS 4.x" ;;
    apigw:*) echo "AWS Config api-gw-access-logging" ;;

    nsg:pci_dss) echo "PCI DSS 10.2.1" ;;
    nsg:hipaa) echo "HIPAA §164.312(b)" ;;
    nsg:soc2) echo "SOC2 CC7.2" ;;
    nsg:iso27001) echo "ISO 27001 A.8.16" ;;
    nsg:nist_800_53|nsg:fedramp) echo "NIST AU-12 / SC-7" ;;
    nsg:gdpr) echo "GDPR Art.30" ;;
    nsg:nis2) echo "NIS2 Art.21(2)(i)" ;;
    nsg:cis_v600) echo "CIS Azure 6.x" ;;
    nsg:*) echo "Azure flow-logs-enabled" ;;
  esac
}

# --- assertion filters (shared by the gate and --self-test) ----------------
# Every plaintext-HTTP ALB listener must redirect to HTTPS (no cleartext in transit).
FILTER_ELB_NOPLAINTEXT='
  [ .resource_changes[]
    | select(.type=="aws_lb_listener")
    | select(((.change.after.protocol // "") | ascii_upcase) == "HTTP")
    | select([ .change.after.default_action[]?
               | select(.type=="redirect" and (.redirect.protocol // "")=="HTTPS") ] | length == 0)
  ] | length == 0'

# Every HTTPS/TLS listener must pin an ssl_policy (no provider-default cipher set).
FILTER_ELB_SSLPOLICY='
  [ .resource_changes[]
    | select(.type=="aws_lb_listener")
    | select(((.change.after.protocol // "") | ascii_upcase) | test("HTTPS|TLS"))
    | select((.change.after.ssl_policy // "") == "")
  ] | length == 0'

# If an application ALB is created, a WAFv2 web-ACL association must exist for it.
FILTER_WAF_ASSOC='
  ([ .resource_changes[] | select(.type=="aws_lb")
     | select((.change.after.load_balancer_type // "application")=="application") ] | length == 0)
  or
  ([ .resource_changes[] | select(.type=="aws_wafv2_web_acl_association") ] | length > 0)'

# Every API Gateway stage (v1 or v2) must declare access_log_settings.
FILTER_APIGW_LOGS='
  [ .resource_changes[]
    | select(.type=="aws_api_gateway_stage" or .type=="aws_apigatewayv2_stage")
    | select((.change.after.access_log_settings | length) == 0)
  ] | length == 0'

# --- Azure equivalents (same "internal/plan-only resource" rationale) ------
# Every Application Gateway must pin a modern TLS floor: ssl_policy with
# min_protocol_version TLSv1_2/TLSv1_3, or a predefined policy_name from 2017S/2022.
FILTER_AGW_TLS='
  [ .resource_changes[]
    | select(.type=="azurerm_application_gateway")
    | select([ .change.after.ssl_policy[]?
               | select(((.min_protocol_version // "") | test("TLSv1_2|TLSv1_3"))
                     or ((.policy_name // "") | test("2022|20170401S"))) ] | length == 0)
  ] | length == 0'

# Every Application Gateway must front a WAF: a WAF_v2/WAF sku tier or a
# firewall_policy_id association.
FILTER_AGW_WAF='
  [ .resource_changes[]
    | select(.type=="azurerm_application_gateway")
    | select(((.change.after.firewall_policy_id // "") == "")
         and ([ .change.after.sku[]? | select((.tier // "") | test("WAF")) ] | length == 0))
  ] | length == 0'

# If an API Management service is created, a diagnostic (logging) must exist.
FILTER_APIM_DIAG='
  ([ .resource_changes[] | select(.type=="azurerm_api_management") ] | length == 0)
  or
  ([ .resource_changes[] | select(.type=="azurerm_api_management_diagnostic") ] | length > 0)'

# If a network security group is created, an NSG/Network Watcher flow log must exist.
FILTER_NSG_FLOW='
  ([ .resource_changes[] | select(.type=="azurerm_network_security_group") ] | length == 0)
  or
  ([ .resource_changes[] | select(.type=="azurerm_network_watcher_flow_log") ] | length > 0)'

# --- self-test: feed canned plans, assert pass/fail (no terraform) ---------
if [ "${1:-}" = "--self-test" ]; then
  t=0; bad=0
  expect() { # $1=desc $2=expected(0/1) $3=json $4=filter
    t=$((t+1))
    if echo "$3" | jq -e "$4" >/dev/null; then got=0; else got=1; fi
    if [ "$got" -eq "$2" ]; then echo "  ok   $1"; else echo "  FAIL $1 (want $2 got $got)"; bad=1; fi
  }
  HTTP_REDIRECT='{"resource_changes":[{"type":"aws_lb_listener","change":{"after":{"protocol":"HTTP","default_action":[{"type":"redirect","redirect":{"protocol":"HTTPS"}}]}}}]}'
  HTTP_PLAIN='{"resource_changes":[{"type":"aws_lb_listener","change":{"after":{"protocol":"HTTP","default_action":[{"type":"forward"}]}}}]}'
  HTTPS_NOPOL='{"resource_changes":[{"type":"aws_lb_listener","change":{"after":{"protocol":"HTTPS","ssl_policy":""}}}]}'
  HTTPS_POL='{"resource_changes":[{"type":"aws_lb_listener","change":{"after":{"protocol":"HTTPS","ssl_policy":"ELBSecurityPolicy-TLS13-1-2-2021-06"}}}]}'
  ALB_NOWAF='{"resource_changes":[{"type":"aws_lb","change":{"after":{"load_balancer_type":"application"}}}]}'
  ALB_WAF='{"resource_changes":[{"type":"aws_lb","change":{"after":{"load_balancer_type":"application"}}},{"type":"aws_wafv2_web_acl_association","change":{"after":{}}}]}'
  STAGE_NOLOG='{"resource_changes":[{"type":"aws_api_gateway_stage","change":{"after":{"access_log_settings":[]}}}]}'
  STAGE_LOG='{"resource_changes":[{"type":"aws_apigatewayv2_stage","change":{"after":{"access_log_settings":[{"destination_arn":"arn:x"}]}}}]}'
  expect "elb redirect passes"      0 "$HTTP_REDIRECT" "$FILTER_ELB_NOPLAINTEXT"
  expect "elb plaintext fails"      1 "$HTTP_PLAIN"    "$FILTER_ELB_NOPLAINTEXT"
  expect "elb no ssl_policy fails"  1 "$HTTPS_NOPOL"   "$FILTER_ELB_SSLPOLICY"
  expect "elb ssl_policy passes"    0 "$HTTPS_POL"     "$FILTER_ELB_SSLPOLICY"
  expect "alb without waf fails"    1 "$ALB_NOWAF"     "$FILTER_WAF_ASSOC"
  expect "alb with waf passes"      0 "$ALB_WAF"       "$FILTER_WAF_ASSOC"
  expect "stage no logs fails"      1 "$STAGE_NOLOG"   "$FILTER_APIGW_LOGS"
  expect "stage with logs passes"   0 "$STAGE_LOG"     "$FILTER_APIGW_LOGS"

  AGW_WEAK='{"resource_changes":[{"type":"azurerm_application_gateway","change":{"after":{"ssl_policy":[{"min_protocol_version":"TLSv1_0"}],"sku":[{"tier":"Standard_v2"}]}}}]}'
  AGW_TLS12='{"resource_changes":[{"type":"azurerm_application_gateway","change":{"after":{"ssl_policy":[{"min_protocol_version":"TLSv1_2"}],"sku":[{"tier":"WAF_v2"}],"firewall_policy_id":"/x"}}}]}'
  AGW_NOWAF='{"resource_changes":[{"type":"azurerm_application_gateway","change":{"after":{"ssl_policy":[{"min_protocol_version":"TLSv1_2"}],"sku":[{"tier":"Standard_v2"}],"firewall_policy_id":""}}}]}'
  APIM_NODIAG='{"resource_changes":[{"type":"azurerm_api_management","change":{"after":{}}}]}'
  APIM_DIAG='{"resource_changes":[{"type":"azurerm_api_management","change":{"after":{}}},{"type":"azurerm_api_management_diagnostic","change":{"after":{}}}]}'
  NSG_NOFLOW='{"resource_changes":[{"type":"azurerm_network_security_group","change":{"after":{}}}]}'
  NSG_FLOW='{"resource_changes":[{"type":"azurerm_network_security_group","change":{"after":{}}},{"type":"azurerm_network_watcher_flow_log","change":{"after":{}}}]}'
  expect "agw weak TLS fails"        1 "$AGW_WEAK"    "$FILTER_AGW_TLS"
  expect "agw TLS1.2 passes"         0 "$AGW_TLS12"   "$FILTER_AGW_TLS"
  expect "agw WAF sku passes"        0 "$AGW_TLS12"   "$FILTER_AGW_WAF"
  expect "agw no WAF fails"          1 "$AGW_NOWAF"   "$FILTER_AGW_WAF"
  expect "apim no diag fails"        1 "$APIM_NODIAG" "$FILTER_APIM_DIAG"
  expect "apim with diag passes"     0 "$APIM_DIAG"   "$FILTER_APIM_DIAG"
  expect "nsg no flow log fails"     1 "$NSG_NOFLOW"  "$FILTER_NSG_FLOW"
  expect "nsg with flow log passes"  0 "$NSG_FLOW"    "$FILTER_NSG_FLOW"
  echo "=== self-test: $t checks, $([ $bad -eq 0 ] && echo PASS || echo FAIL) ==="
  exit $bad
fi

# --- live gate -------------------------------------------------------------
PLAN_FILE="${1:-tfplan}"
[ -f "${PLAN_FILE}" ] || { echo "usage: plan-gate.sh <planfile> [framework]  |  plan-gate.sh --self-test"; exit 2; }

JSON="${PLAN_JSON:-$(terraform show -json "${PLAN_FILE}")}"
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

echo "=== plan-gate: ${PLAN_FILE} (framework: ${FW}) ==="

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

# Edge/transit controls the source-time transforms cannot reach (internal
# module resources). Clause IDs vary by framework; assertions do not.
check "ELB: no cleartext HTTP listener [$(cite elb)]"        "${FILTER_ELB_NOPLAINTEXT}"
check "ELB: HTTPS listeners pin an ssl_policy [$(cite elb)]" "${FILTER_ELB_SSLPOLICY}"
check "WAF: app ALB has a web-ACL association [$(cite waf)]" "${FILTER_WAF_ASSOC}"
check "API Gateway: stage has access logging [$(cite apigw)]" "${FILTER_APIGW_LOGS}"

# Azure equivalents — internal/plan-only resources a source-time force can't reach.
check "App Gateway: TLS floor TLSv1_2+ [$(cite elb)]"          "${FILTER_AGW_TLS}"
check "App Gateway: WAF sku or firewall policy [$(cite waf)]"  "${FILTER_AGW_WAF}"
check "API Management: diagnostic logging set [$(cite apigw)]"  "${FILTER_APIM_DIAG}"
check "NSG: flow log enabled [$(cite nsg)]"                     "${FILTER_NSG_FLOW}"

if [ "${fail}" -ne 0 ]; then
  echo "=== plan-gate: VIOLATIONS FOUND ==="
  exit 1
fi
echo "=== plan-gate: all controls satisfied ==="
