# tf-drift-detection Orb

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
