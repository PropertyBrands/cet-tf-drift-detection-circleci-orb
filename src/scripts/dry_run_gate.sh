#!/usr/bin/env bash
set -euo pipefail

: "${DRY_RUN:?DRY_RUN must be set to 'true' or 'false'}"

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry run enabled; stopping before Terragrunt/SES steps."
  exit 0
fi
