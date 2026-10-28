#!/usr/bin/env bash
# Optional status POST. Off unless the job sets report_webhook: true.
# DRIFT_WEBHOOK_URL and DRIFT_WEBHOOK_TOKEN come from the job environment.
set -uo pipefail

if [[ "${REPORT_WEBHOOK:-}" != "true" ]]; then
  exit 0
fi

if [[ -z "${DRIFT_WEBHOOK_URL:-}" || -z "${DRIFT_WEBHOOK_TOKEN:-}" ]]; then
  echo "Drift webhook is not configured. Skipping."
  exit 0
fi

python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request

url = os.environ["DRIFT_WEBHOOK_URL"]
token = os.environ["DRIFT_WEBHOOK_TOKEN"]
report = "/tmp/drift-report.json"

if os.path.isfile(report):
    with open(report) as handle:
        payload = json.load(handle)
else:
    payload = {
        "repo": "%s/%s" % (
            os.environ.get("CIRCLE_PROJECT_USERNAME", "unknown"),
            os.environ.get("CIRCLE_PROJECT_REPONAME", "unknown"),
        ),
        "job": os.environ.get("CIRCLE_JOB", "unknown"),
        "region": os.environ.get("REGION", ""),
        "account_type": os.environ.get("ACCOUNT_TYPE", ""),
        "environment": os.environ.get("ENVIRONMENT", ""),
        "account_id": os.environ.get("ACCOUNT_ID", ""),
        "account_alias": "",
        "exit_code": 1,
        "summary": "Job failed before the plan finished.",
        "pipeline_url": os.environ.get("CIRCLE_BUILD_URL", ""),
        "commit_sha": os.environ.get("CIRCLE_SHA1", ""),
    }

body = json.dumps(payload).encode()
request = urllib.request.Request(
    url,
    data=body,
    headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        print("Drift status accepted for %s %s (%s)" % (payload["repo"], payload["job"], response.status))
except urllib.error.URLError as exc:
    print("WARN: drift webhook failed: %s" % exc)
PY
