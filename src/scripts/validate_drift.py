#!/usr/bin/env python3
"""
Script to validate Terraform drift changes against allowed resource type and key combinations.
Exits with error code 1 if any drift changes are not in the allowed list.

Usage:
    python validate_drift.py <drift_file> [--allowed-changes <allowed_changes_file>]

Arguments:
    drift_file                  Path to the drift changes JSON file
    --allowed-changes           Optional path to a file containing allowed changes
                               (one per line in format 'resource_type:key')
                               If not provided, uses default hardcoded list
"""

import json
import sys
import os
import argparse


def main():
    # Set up argument parser.
    parser = argparse.ArgumentParser(
        description="Validate Terraform drift changes against allowed resource type and key combinations"
    )
    parser.add_argument("drift_file", help="Path to the drift changes JSON file")
    parser.add_argument(
        "--allowed-changes",
        help="Path to a file containing allowed changes (one per line in format 'resource_type:key')",
    )

    # Parse arguments.
    args = parser.parse_args()
    drift_file = args.drift_file

    # Load allowed changes from file or use defaults.
    if args.allowed_changes:
        # Load allowed changes from file.
        if not os.path.exists(args.allowed_changes):
            print(f"Error: {args.allowed_changes} not found", file=sys.stderr)
            sys.exit(1)

        try:
            with open(args.allowed_changes, "r") as f:
                allowed_changes = [
                    line.strip()
                    for line in f
                    if line.strip() and not line.strip().startswith("#")
                ]
            print(
                f"Using custom list of allowed drift changes from file: {args.allowed_changes}"
            )
        except Exception as e:
            print(f"Error reading {args.allowed_changes}: {e}", file=sys.stderr)
            sys.exit(1)

        if not allowed_changes:
            print(
                f"Error: No valid allowed changes found in {args.allowed_changes}",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        # Default list of allowed resource_type:key combinations.
        allowed_changes = [
            "aws_eks_cluster:platform_version",
            "aws_eks_addon:modified_at",
            "aws_eks_access_policy_association:access_scope",
        ]

    # Check if file exists.
    if not os.path.exists(drift_file):
        print(f"Error: {drift_file} not found", file=sys.stderr)
        sys.exit(1)

    try:
        # Load the drift changes JSON.
        with open(drift_file, "r") as f:
            drift_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {drift_file}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {drift_file}: {e}", file=sys.stderr)
        sys.exit(1)

    # Print allowed changes for tracking purposes.
    print(f"Checking drift against following allowed changes:")
    for change in allowed_changes:
        print(f"  - {change}")

    # Track any violations.
    violations = []

    # Iterate over each drift object.
    for drift_obj in drift_data:
        resource_type = drift_obj.get("resource_type", "")
        changed_keys = drift_obj.get("changed_keys", [])
        address = drift_obj.get("address", "")

        # Check each changed key.
        for key in changed_keys:
            change_identifier = f"{resource_type}:{key}"

            if change_identifier not in allowed_changes:
                violations.append(
                    {
                        "address": address,
                        "resource_type": resource_type,
                        "changed_key": key,
                        "change_identifier": change_identifier,
                    }
                )

    # Report results.
    if violations:
        print(
            "\n❌ At least one drift change cannot be auto-adopated into Terraform state:",
            file=sys.stderr,
        )
        print("", file=sys.stderr)

        for violation in violations:
            print(f"  Resource: {violation['address']}", file=sys.stderr)
            print(f"  Type: {violation['resource_type']}", file=sys.stderr)
            print(f"  Changed Key: {violation['changed_key']}", file=sys.stderr)
            print(f"  Identifier: {violation['change_identifier']}", file=sys.stderr)
            print("", file=sys.stderr)

        sys.exit(1)
    else:
        print("\n✅ All drift changes can be auto-adopated into Terraform state")
        print(f"Validated {len(drift_data)} drift objects")

        # Show what was validated.
        for drift_obj in drift_data:
            resource_type = drift_obj.get("resource_type", "")
            changed_keys = drift_obj.get("changed_keys", [])

            for key in changed_keys:
                print(f"  ✓ {resource_type}:{key}")


if __name__ == "__main__":
    main()
