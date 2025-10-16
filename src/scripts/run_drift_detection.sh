#!/usr/bin/env bash
set -euo pipefail
apk add --no-cache jq >/dev/null || true

# Build exclude flag for run-all
EXTRA_ARGS=()
if [ -n "${TG_QUEUE_EXCLUDE_DIRS:-}" ]; then
  IFS=',' read -r -a _dirs <<< "$TG_QUEUE_EXCLUDE_DIRS"
  for d in "${_dirs[@]}"; do
    d="$(echo "$d" | xargs)"
    [ -n "$d" ] && EXTRA_ARGS+=( --terragrunt-exclude-dir "$d" )
  done
fi

# Fetch the account name (alias) and if missing use account_id
ACCOUNT_ALIAS=$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null || true)
# Convert to empty string if None is returned
[ "$ACCOUNT_ALIAS" = "None" ] && ACCOUNT_ALIAS=""
ALIAS="${ACCOUNT_ALIAS:-<< parameters.account_id >>}"

# Run tg plan and capture the exit code
set +e
terragrunt run-all plan -detailed-exitcode --terragrunt-non-interactive "${EXTRA_ARGS[@]}"
TG_STATUS=$?
set -e

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
    SUBJECT="[TF] Drift detected in ${ALIAS} - << parameters.account_type >> account (environment: << parameters.environment >>)"
    BODY=$(printf '%s\nAWS Account Name: %s\nAWS Account ID: %s\nAWS Region: %s\nAccount Type: %s\nEnvironment: %s\nPipeline: %s\n' \
    "Drift detected:" \
    "$ALIAS" \
    "<< parameters.account_id >>" \
    "<< parameters.region >>" \
    "<< parameters.account_type >>" \
    "<< parameters.environment >>" \
    "${CIRCLE_BUILD_URL}")
    send_mail "$SUBJECT" "$BODY"
    echo "Drift detected in the Terragrunt plan. SES notification sent."
    exit 2
    ;;
  0)
    echo "No drift. Plan OK."
    ;;
  *)
    SUBJECT="[TF] Terragrunt Plan failed in ${ALIAS} - << parameters.account_type >> account (environment: << parameters.environment >>)"
    BODY=$(printf 'Terragrunt plan failed (exit %s)\nAWS Account Name: %s\nAWS Account ID: %s\nAWS Region: %s\nAccount Type: %s\nEnvironment: %s\nPipeline: %s\n' \
    "$TG_STATUS" \
    "$BRAND" \
    "<< parameters.account_id >>" \
    "<< parameters.region >>" \
    "<< parameters.account_type >>" \
    "<< parameters.environment >>" \
    "${CIRCLE_BUILD_URL}")
    send_mail "$SUBJECT" "$BODY"
    echo "Terragrunt Plan failed. SES notification sent."
    exit "$TG_STATUS"
    ;;
esac
