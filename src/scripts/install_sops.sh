#!/usr/bin/env bash
set -e
apk add --no-cache curl
curl -sSLo /usr/local/bin/sops \
  https://github.com/getsops/sops/releases/download/v3.10.2.linux.amd64
chmod +x /usr/local/bin/sops
