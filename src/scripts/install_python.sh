#!/usr/bin/env bash
set -e
apk add --no-cache python3
ln -sf /usr/bin/python3 /usr/bin/python
python --version
