#!/usr/bin/env bash
# Register a fleet self-hosted GitHub Actions runner for ONE repo.
#
# Personal GitHub accounts have no shared/org runner groups, so every repo
# that targets `self-hosted` needs its own runner instance. This makes that
# a one-command step. Run from the Mac:
#
#   bash scripts/add-runner.sh <repo-name>
#
# Requires: gh (authed, repo admin), SSH access to the runner host.
# The runner self-updates on first connect, so a stale runner.tgz is fine;
# refresh it from https://github.com/actions/runner/releases if config.sh
# ever rejects it as too old.
set -euo pipefail

repo=${1:?usage: add-runner.sh <repo-name>}
owner="hemanth1986"
host="root@100.101.144.15" # Hetzner website VPS (Vault: Servers-Devices.md)

token=$(gh api -X POST "repos/$owner/$repo/actions/runners/registration-token" --jq .token)

ssh -o BatchMode=yes "$host" "read -r TOK
  set -e
  if [ -d /opt/actions-runner/$repo ]; then
    echo 'ERROR: /opt/actions-runner/$repo already exists' >&2
    exit 1
  fi
  mkdir -p /opt/actions-runner/$repo
  tar xzf /opt/actions-runner/runner.tgz -C /opt/actions-runner/$repo
  chown -R ghrunner:ghrunner /opt/actions-runner/$repo
  cd /opt/actions-runner/$repo
  sudo -u ghrunner ./config.sh --url https://github.com/$owner/$repo \
    --token \"\$TOK\" --name hetzner-$repo --labels hetzner --unattended
  ./svc.sh install ghrunner
  ./svc.sh start" <<<"$token"

gh api "repos/$owner/$repo/actions/runners" \
  --jq '.runners[] | .name + ": " + .status'
