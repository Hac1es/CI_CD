#!/usr/bin/env bash
set -euo pipefail
for h in 34.21.161.118 10.0.3.2 10.0.3.3 10.0.2.2 10.0.2.3; do
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$h" >/dev/null
done