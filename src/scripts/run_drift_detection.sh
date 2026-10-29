#!/usr/bin/env bash
set -euo pipefail

DEFAULT_WD="${DEPLOYMENTS_ROOT}/${ACCOUNT_TYPE}/${REGION}/${ENVIRONMENT}"
WD="${WORKING_DIR_OVERRIDE:-$DEFAULT_WD}"
if [ ! -d "$WD" ]; then
  echo "ERROR: working directory '$WD' does not exist" >&2
  exit 66
fi
echo "Running drift detection in: $WD"
cd "$WD"

# Build exclude flag for run-all
EXTRA_ARGS=()
if [ -n "${TG_QUEUE_EXCLUDE_DIRS:-}" ]; then
  IFS=',' read -r -a _dirs <<< "$TG_QUEUE_EXCLUDE_DIRS"
  for d in "${_dirs[@]}"; do
    d="$(echo "$d" | xargs)"
    [ -n "$d" ] && EXTRA_ARGS+=( --queue-exclude-dir "$d" )
  done
fi

# Fetch the account name (alias) and if missing use account_id
ACCOUNT_ALIAS=$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null || true)
# Convert to empty string if None is returned
if [ "$ACCOUNT_ALIAS" = "None" ] || [ -z "$ACCOUNT_ALIAS" ]; then
  ALIAS="$ACCOUNT_ID"
else
  ALIAS="$ACCOUNT_ALIAS"
fi

# Exit 2 is drift only when a saved plan changes a real resource or an output
# outside the EKS version catalog. Catalog-only plans are refreshed into state.
refresh_catalog_outputs() {
  local plans_file plan_file rel unit unit_dir json class show_status apply_status
  local saw_catalog=0
  local apply_failed=0
  plans_file="$(mktemp)"
  find "$PLAN_OUT" -type f -name 'tfplan.tfplan' | sort > "$plans_file"
  if [[ ! -s "$plans_file" ]]; then
    rm -f "$plans_file"
    echo "No saved plans to classify. Leaving the drift result unchanged."
    return 1
  fi
  local catalog_units=()
  while IFS= read -r plan_file; do
    rel="${plan_file#"$PLAN_OUT"/}"
    unit="${rel%/tfplan.tfplan}"
    unit_dir="${PWD}/${unit}"
    json="$(mktemp)"
    set +e
    terragrunt run --working-dir "$unit_dir" -- show -json "$plan_file" > "$json"
    show_status=$?
    set -e
    if [[ "$show_status" != "0" ]]; then
      rm -f "$json"
      rm -f "$plans_file"
      echo "Could not read plan for ${unit}. Leaving the drift result unchanged."
      return 1
    fi
    set +e
    python3 /tmp/validate_drift.py --plan-class "$json"
    class=$?
    set -e
    rm -f "$json"
    if [[ "$class" == "0" ]]; then
      saw_catalog=1
      catalog_units+=("$unit_dir")
    elif [[ "$class" == "10" ]]; then
      :
    else
      rm -f "$plans_file"
      return 1
    fi
  done < "$plans_file"
  rm -f "$plans_file"
  if [[ "$saw_catalog" != "1" ]]; then
    return 1
  fi
  case "${DRY_RUN:-}" in
    true|True|TRUE|1)
      echo "Dry run: EKS version-catalog outputs would be refreshed. Still reporting drift."
      return 1
      ;;
  esac
  for unit_dir in "${catalog_units[@]}"; do
    echo "Refreshing EKS version-catalog outputs into state: ${unit_dir}"
    set +e
    terragrunt run --working-dir "$unit_dir" -- apply -refresh-only -auto-approve
    apply_status=$?
    set -e
    if [[ "$apply_status" != "0" ]]; then
      apply_failed=1
    fi
  done
  [[ "$apply_failed" == "0" ]]
}

# Run tg plan and capture the exit code
PLAN_OUT="${TMPDIR:-/tmp}/drift-plans"
rm -rf "$PLAN_OUT"
set +e
terragrunt run --all --parallelism 1 --non-interactive "${EXTRA_ARGS[@]}" --out-dir "$PLAN_OUT" -- plan -detailed-exitcode
TG_STATUS=$?
set -e

CATALOG_REFRESHED=
if [[ "$TG_STATUS" == "2" ]]; then
  if refresh_catalog_outputs; then
    TG_STATUS=0
    CATALOG_REFRESHED=1
  fi
fi

# Optional status POST. The file is read by a later step that still runs
# when this step exits non-zero. Absent unless report_webhook is true.
# Set inside the script so a boolean parameter stays the string true.
REPORT_WEBHOOK="<< parameters.report_webhook >>"
case "${REPORT_WEBHOOK:-}" in
  true|True|TRUE|1) REPORT_WEBHOOK=true ;;
  *) REPORT_WEBHOOK= ;;
esac
if [[ "${REPORT_WEBHOOK}" == "true" ]]; then
  if [[ "$CATALOG_REFRESHED" == "1" ]]; then
    SUMMARY="EKS version catalog refreshed into state."
  elif [[ "$TG_STATUS" == "0" ]]; then
    SUMMARY="No changes."
  elif [[ "$TG_STATUS" == "2" ]]; then
    SUMMARY="Drift detected."
  else
    SUMMARY="Plan failed (exit ${TG_STATUS})."
  fi
  jq -n \
    --arg repo "${CIRCLE_PROJECT_USERNAME:-unknown}/${CIRCLE_PROJECT_REPONAME:-unknown}" \
    --arg job "${CIRCLE_JOB:-unknown}" \
    --arg region "${REGION}" \
    --arg account_type "${ACCOUNT_TYPE}" \
    --arg environment "${ENVIRONMENT}" \
    --arg account_id "${ACCOUNT_ID}" \
    --arg account_alias "${ALIAS}" \
    --argjson exit_code "$TG_STATUS" \
    --arg summary "$SUMMARY" \
    --arg pipeline_url "${CIRCLE_BUILD_URL:-}" \
    --arg commit_sha "${CIRCLE_SHA1:-}" \
    '{repo:$repo, job:$job, region:$region, account_type:$account_type, environment:$environment, account_id:$account_id, account_alias:$account_alias, exit_code:$exit_code, summary:$summary, pipeline_url:$pipeline_url, commit_sha:$commit_sha}' \
    > /tmp/drift-report.json
fi

# Helper to send a minimal SES email with jq
send_mail() {
    subj="$1"
    body="$2"
    FROM_COMPOSED="${DRIFT_EMAIL_FROM_NAME} <${DRIFT_EMAIL_FROM}>"

    jq -n --arg s "$subj" --arg b "$body" \
        '{Subject:{Data:$s}, Body:{Text:{Data:$b}}}' > /tmp/message.json

    # Ensure we don't sign with assumed-role tokens
    unset AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE

    AWS_ACCESS_KEY_ID="$SES_LOGIN" \
    AWS_SECRET_ACCESS_KEY="$SES_PASSWORD" \
    AWS_DEFAULT_REGION="$SES_REGION" \
    aws ses send-email \
        --from "$FROM_COMPOSED" \
        --destination "ToAddresses=$DRIFT_EMAIL_TO" \
        --message file:///tmp/message.json \
    || echo "WARN: SES send failed"
}

case "$TG_STATUS" in
  2)
    SUBJECT="[TF] Drift detected in ${ALIAS} account (environment: ${ENVIRONMENT})"
    BODY=$(printf '%s\nAWS Account Name: %s\nAWS Account ID: %s\nAWS Region: %s\nAccount Type: %s\nEnvironment: %s\nPipeline: %s\n' \
      "Drift detected:" \
      "$ALIAS" \
      "$ACCOUNT_ID" \
      "$REGION" \
      "$ACCOUNT_TYPE" \
      "$ENVIRONMENT" \
      "${CIRCLE_BUILD_URL:-N/A}")
    send_mail "$SUBJECT" "$BODY"
    echo "Drift detected in the Terragrunt plan. SES notification sent."
    exit 2
    ;;
  0)
    if [[ "$CATALOG_REFRESHED" == "1" ]]; then
      echo "EKS version-catalog outputs were refreshed into state. Not reporting drift."
    else
      echo "No drift. Plan OK."
    fi
    ;;
  *)
    SUBJECT="[TF] Terragrunt plan failed in ${ALIAS} account (environment: ${ENVIRONMENT})"
    BODY=$(printf 'Terragrunt plan failed (exit code %s)\nAWS Account Name: %s\nAWS Account ID: %s\nAWS Region: %s\nAccount Type: %s\nEnvironment: %s\nPipeline: %s\n' \
      "$TG_STATUS" \
      "$ALIAS" \
      "$ACCOUNT_ID" \
      "$REGION" \
      "$ACCOUNT_TYPE" \
      "$ENVIRONMENT" \
      "${CIRCLE_BUILD_URL:-N/A}")
    send_mail "$SUBJECT" "$BODY"
    echo "Terragrunt Plan failed. SES notification sent."
    exit "$TG_STATUS"
    ;;
esac
