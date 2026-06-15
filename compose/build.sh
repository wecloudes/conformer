#!/usr/bin/env bash
# Host-side wrapper — build & upload a hardened module via the builder service.
#
#   ./build.sh <framework> <module> <version> [namespace] [provider]
#   ./build.sh cis_v600 s3-bucket 5.11.0
#   ./build.sh soc2 s3-bucket 5.11.0
set -euo pipefail
cd "$(dirname "$0")"
exec docker compose --profile build run --rm builder "$@"
