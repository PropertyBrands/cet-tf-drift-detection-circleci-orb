# tf-drift-detection Orb

## Behavior

### First: Attempt to auto-adopt list of approved drift changes into Terraform state
For each processed Terragrunt deployment, this Orb will automatically adopt
any drift into its state file if _all_ of the drift falls into a set of
pre-approved combinations of resource types and keys.

By default, the following combinations are auto-approved:
```
aws_eks_cluster:platform_version
aws_eks_addon:modified_at
aws_eks_access_policy_association:access_scope
```

This feature can be:
* Disabled by setting the `auto_adopt_drift` parameter to a (boolean) false
* Adjusted by passing in a file containing a custom list of pre-approved changes using the `pre_approved_drift_file` parameter

### Second
Checks for Terraform drift by running the followig steps.

Runs `terragrunt run-all plan` with support for:
- CircleCI IP ranges (to reach EKS public endpoints behind allowlists),
- Comma-separated `--terragrunt-exclude-dir` handling,
- SES email notifications on **drift** (Terraform exit 2) and **failures** (non-zero non-2),
  - with SES credentials passed via CircleCI Context

## Usage

```yaml
orbs:
  tf-drift: iiq/tf-drift-detection@1.0.1

workflows:
  drift-detection:
    jobs:
      - tf-drift/drift_detection:
          name: terragrunt-plan-us-west-2-dev
          account_type: dev-a
          region: us-west-2
          environment: dev
          account_id: "123456789012"
          role_name: "circleci-terraform"
          tg_queue_exclude_dirs: "dir1,dir2"
          drift_email_to: "devops@example.com"
          drift_email_from: "terraform@alerts.example.com"
          ses_region: "us-west-2"
          context: ses-creds
```

## Development

### Building the Orb

#### Automatically build via `make`
The easiest way to build this orb is via the `make` command:
```bash
make build
```

#### Manually building the orb
This orb uses a build script to maintain Python code as a single source of truth. Before packing the orb:

```bash
# Generate the Python wrapper script (only needed if validate_drift.py changed)
./scripts/generate_python_wrapper.sh

# Pack the orb
circleci orb pack src > orb.yml
```

### Development Workflow

1. Make changes to source files in `src/`
2. If you modified `src/scripts/validate_drift.py`, run `./scripts/generate_python_wrapper.sh`
3. Pack and validate: `make build`
4. Commit all changes including generated files

See `scripts/README.md` for more details on the build process.
