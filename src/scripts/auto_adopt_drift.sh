#!/usr/bin/env bash
# @brief Refresh all Terragrunt units and auto-adopt pre-approved drift changes into Terraform state.
set -euo pipefail

# Constants.
SCRIPT_PATH="${PWD}"
echo "SCRIPT_PATH: ${SCRIPT_PATH}"
TG_UNIT_FILE="terragrunt_units.txt"
TG_REFRESH_OUTDIR="${SCRIPT_PATH}/refresh/"

# Determine exclusions for Terragrunt find / run commands.
TF_FIND_FILTER_FLAGS=()
TF_RUN_QUEUE_EXCLUDE_DIRS=()
if [ -n "${TG_EXCLUDE_DIRS:-}" ]; then
  # Read comma-separated list into array.
  IFS=',' read -r -a _dirs <<< "$TG_EXCLUDE_DIRS"

  # Iterate over array and add --queue-exclude-dir flags.
  for d in "${_dirs[@]}"; do
    # Remove leading/trailing whitespace.
    d="$(echo "$d" | xargs)"

    # Only add flag if directory is not empty.
    if [ -n "$d" ]; then
      TF_FIND_FILTER_FLAGS+=( --filter \!"$d" )
      TF_RUN_QUEUE_EXCLUDE_DIRS+=( --queue-exclude-dir "$d" )
    fi
  done
fi

# Determine Terragrunt units, exit if none found.
terragrunt find --experiment filter-flag "${TF_FIND_FILTER_FLAGS[@]}" > "${TG_UNIT_FILE}"
if [[ ! -s "${TG_UNIT_FILE}" ]]; then
  printf "\n\nNo Terragrunt units found, exiting.\n"
  exit 0
fi

printf "\n\nInitiate process to refresh all Terragrunt units and auto-adopt pre-approved drift changes into state.\n"
printf "Processing following Terragrunt units: \n%s\n" "$(cat ${TG_UNIT_FILE})"

# Run refresh on all units.
set +e
terragrunt run --all "${TF_RUN_QUEUE_EXCLUDE_DIRS[@]}" --out-dir "${TG_REFRESH_OUTDIR}" -- plan -refresh-only -detailed-exitcode
set -e

# Copy all Terraform plan files into their respective Terragrunt unit directories and convert them to a JSON file.
while read -r unit; do
  ### Helper variables.
  # Directory of the Terragrunt unit.
  unit_dir="${SCRIPT_PATH}/${unit}"

  # Refresh plan file in .tfplan format.
  refresh_file_tfplan="${unit_dir}/refresh.tfplan"

  # Refresh plan file in JSON format.
  refresh_file_json="${unit_dir}/refresh.json"

  # Drift file in JSON format.
  drift_file_json="${unit_dir}/drift.json"

  # Copy the refresh plan file to the unit directory.
  cp "${TG_REFRESH_OUTDIR}/${unit}/tfplan.tfplan" "${refresh_file_tfplan}"

  # Convert refresh.tfplan to a JSON file.
  printf "\n\n\n==================================================\n"
  printf "Processing Terraform unit: %s\n" "${unit}"
  printf "Converting Terraform plan file to JSON for: %s\n" "${unit}"
  terragrunt run --working-dir "${unit_dir}" -- show -json "${refresh_file_tfplan}" > "${refresh_file_json}"

  # Check if any drift changes were found, otherwise skip to next unit.
  has_drift_changes=$(jq 'has("resource_drift")' "${refresh_file_json}")
  if [[ "$has_drift_changes" == "false" ]]; then
    echo "No drift changes found, skipping to next Terragrunt unit"
    continue
  fi

  # Extract drift into second JSON object for further processing.
  jq '[.resource_drift[] | {
    address: .address,
    resource_type: (.address | split(".") | .[-2]),
    changed_keys: [
      (.change.before // {}) as $before |
      (.change.after // {}) as $after |
      ([$before, $after] | add | keys_unsorted[]) as $key |
      select($before[$key] != $after[$key]) |
      $key
    ]
  }]' "${refresh_file_json}" > "${drift_file_json}"

  # Check each drift change to see if it can be auto-adopted.
  printf "Validating drift for: %s\n" "${unit}"
  set +e
  if [[ -n "${PRE_APPROVED_DRIFT_FILE:-}" ]]; then
    # Determine absolute path to pre-approved drift file.
    pre_approved_drift_file_abs="$(git rev-parse --show-toplevel || echo .)/${PRE_APPROVED_DRIFT_FILE}"
    python3 /tmp/validate_drift.py "${drift_file_json}" --allowed-changes "${pre_approved_drift_file_abs}"
  else
    python3 /tmp/validate_drift.py "${drift_file_json}"
  fi
  python_exit_code="$?"
  set -e

  # Auto-adopt drift if all changes are on the list of allowed changes.
  if [[ "${python_exit_code}" == "0" ]]; then
    printf "\n\n==> Auto-remediating drift by running apply with refresh-only"
    # terragrunt run --working-dir "${unit_dir}" -- apply -refresh-only
  else
    printf "\n\n==> Drift cannot be auto-remediated"
  fi

done < "${TG_UNIT_FILE}"

