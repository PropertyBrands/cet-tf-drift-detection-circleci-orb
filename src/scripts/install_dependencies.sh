#!/usr/bin/env bash
set -euo pipefail
apk add --no-cache bind-tools jq python3

# Create symlink for Python 3 to Python.
ln -sf /usr/bin/python3 /usr/bin/python
python --version
