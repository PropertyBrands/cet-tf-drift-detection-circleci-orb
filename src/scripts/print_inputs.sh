#!/usr/bin/env bash
set -euo pipefail
echo "drift-detection inputs:"
echo "  region:                << parameters.region >>"
echo "  account_type:          << parameters.account_type >>"
echo "  environment:           << parameters.environment >>"
echo "  account_id:            << parameters.account_id >>"
echo "  deployments_root:      << parameters.deployments_root >>"
echo "  role_name:             << parameters.role_name >>"
echo "  terragrunt_image:      << parameters.terragrunt_image >>"
echo "  tg_queue_exclude_dirs: << parameters.tg_queue_exclude_dirs >>"
echo "  drift_email_to:        << parameters.drift_email_to >>"
echo "  drift_email_from:      << parameters.drift_email_from >>"
echo "  drift_email_from_name: << parameters.drift_email_from_name >>"
echo "  ses_region:            << parameters.ses_region >>"
echo "  dry_run:               << parameters.dry_run >>"
if [ -n "${SES_LOGIN:-}" ]; then echo "  SES_LOGIN:             [set]"; else echo "  SES_LOGIN:             [unset]"; fi
