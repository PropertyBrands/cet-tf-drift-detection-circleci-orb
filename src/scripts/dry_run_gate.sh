#!/usr/bin/env bash
set -euo pipefail
if [ "<< parameters.dry_run >>" = "true" ]; then
  echo "Dry run enabled; stopping before Terragrunt/SES steps."
  exit 0
fi
