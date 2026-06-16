#!/usr/bin/env bash
# Interface-preservation guard — verify a patched module is still a DROP-IN
# replacement for its upstream (so consumers swap only the `source` host).
#
# Fails if a transformation breaks the module's PUBLIC CONTRACT:
#   - removes or renames an upstream `variable`
#   - removes or renames an upstream `output`
#   - introduces a NEW REQUIRED variable (new variables must carry a `default`)
#
# Adding new variables WITH defaults, changing existing defaults, mutating
# resource bodies, and injecting `check` blocks are all allowed — they do not
# change the interface a caller depends on.
#
#   check-interface.sh <upstream_dir> <patched_dir>
#
# Only the module ROOT is checked (top-level *.tf) — that is the public surface
# a caller binds to; submodules are internal. Set SKIP_INTERFACE_CHECK=true to
# bypass (not recommended).
set -euo pipefail

UP="${1:?upstream_dir}"
PT="${2:?patched_dir}"

if [ "${SKIP_INTERFACE_CHECK:-false}" = "true" ]; then
  echo "  interface check skipped (SKIP_INTERFACE_CHECK=true)"
  exit 0
fi

# Emit "<name> <required:0|1>" per variable, or just "<name>" per output, across
# the root *.tf files. Brace-counted so multi-line blocks are handled.
_blocks() {
  local kind="$1" dir="$2"
  # shellcheck disable=SC2046
  awk -v kind="$kind" '
    function flush() {
      if (name != "") { print (kind=="variable" ? name " " hasdef : name); name=""; hasdef=0 }
    }
    $0 ~ "^[[:space:]]*" kind "[[:space:]]+\"" {
      flush(); name=$2; gsub(/"/,"",name); depth=0; started=0
    }
    name != "" {
      for (i=1;i<=length($0);i++){ c=substr($0,i,1); if(c=="{"){depth++;started=1} else if(c=="}")depth-- }
      # a default attribute anywhere in the variable block (line-start or after
      # { / ; / whitespace) means the variable is optional. Only a variable.s own
      # default uses `default =`, so matching block-wide is safe.
      if ($0 ~ /(^|[^A-Za-z0-9_])default[[:space:]]*=/) hasdef=1
      if (started && depth<=0) flush()
    }
    END { flush() }
  ' $(find "$dir" -maxdepth 1 -name '*.tf' 2>/dev/null) 2>/dev/null | sort -u
}

up_vars="$(_blocks variable "$UP" | awk '{print $1}')"
pt_vars="$(_blocks variable "$PT" | awk '{print $1}')"
up_outs="$(_blocks output  "$UP")"
pt_outs="$(_blocks output  "$PT")"
# NEW variables introduced by patching that are REQUIRED (required flag == 0).
new_required="$(comm -13 <(echo "$up_vars") <(_blocks variable "$PT" | awk '$2==0{print $1}' | sort -u))"
removed_vars="$(comm -23 <(echo "$up_vars") <(echo "$pt_vars"))"
removed_outs="$(comm -23 <(echo "$up_outs") <(echo "$pt_outs"))"

fail=0
if [ -n "${removed_vars}" ]; then
  echo "  FAIL interface: upstream variable(s) removed/renamed:"; echo "${removed_vars}" | sed 's/^/    - /'
  fail=1
fi
if [ -n "${removed_outs}" ]; then
  echo "  FAIL interface: upstream output(s) removed/renamed:"; echo "${removed_outs}" | sed 's/^/    - /'
  fail=1
fi
if [ -n "${new_required}" ]; then
  echo "  FAIL interface: new REQUIRED variable(s) added (must have a default):"; echo "${new_required}" | sed 's/^/    - /'
  fail=1
fi

if [ "${fail}" -eq 0 ]; then
  echo "  interface preserved (drop-in): $(echo "$up_vars" | grep -c .) vars, $(echo "$up_outs" | grep -c .) outputs intact"
fi
exit "${fail}"
