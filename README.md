# gha-workflows

Reusable GitHub Actions workflows for the **innovspatial** estate.

## Workflows

### `dokploy-custom-app.yml`

Build, push, deploy, and verify a custom app via Dokploy + Tailscale + Traefik.

**Caller pattern** (in each app repo's `.github/workflows/deploy.yml`):

```yaml
name: Build and Deploy
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      runner:
        description: "Fallback: pick ubuntu-latest if the fleet runner is down (uses metered minutes)"
        type: choice
        options: [self-hosted, ubuntu-latest]
        default: self-hosted

# Required: grant the reusable workflow the permissions it needs.
# Caller MUST grant these — caller's grant is the upper bound for the
# reusable workflow. Without these, the run fails with startup_failure.
permissions:
  contents: read    # actions/checkout
  packages: write   # docker push to GHCR

# Required: one run per ref; queued runs are superseded, a running
# deploy is never cancelled. See "Caller guardrails" below.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

jobs:
  deploy:
    uses: hemanth1986/gha-workflows/.github/workflows/dokploy-custom-app.yml@main
    with:
      app_host: biometric.innovspatial.app
      ghcr_image: ghcr.io/hemanth1986/biometric-sync
      # Fleet Hetzner runner by default; dispatch can fall back to ubuntu-latest.
      runner: ${{ inputs.runner || 'self-hosted' }}
    secrets: inherit
```

**Caller guardrails (mandatory, fleet-wide since 2026-08-21):**

- Every workflow — caller or standalone — declares a workflow-level
  `concurrency` block keyed on `${{ github.workflow }}-${{ github.ref }}`.
  Deploys/builds/releases use `cancel-in-progress: false` (queue; never kill
  a running publish). Checks (lint/test/validate) use `true` (a newer push
  supersedes the in-flight run).
- Every locally-defined job sets an explicit `timeout-minutes`: 15 for
  checks, 30 for builds/releases. Jobs that only `uses:` this reusable
  workflow need no timeout — the reusable job carries `timeout-minutes: 30`.
- Any `apt-get` call adds
  `-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30`
  so a mirror stall fails in seconds instead of hanging.

Why: on 2026-08-19 a stalled apt mirror rode GitHub's 360-minute default
job timeout four times in one afternoon and burned 1,444 of the month's
2,000 free Actions minutes, freezing all private-repo CI until the next
billing cycle.

**Self-hosted runner — the fleet DEFAULT (since 2026-08-21):**

Every fleet workflow runs on the Hetzner runner by default (unmetered
minutes; keeps working while the free-tier quota is exhausted) and carries a
`workflow_dispatch` `runner` input as the manual fallback: if the runner
host is down, dispatch the workflow with `runner: ubuntu-latest` to use
GitHub-hosted (metered) capacity. Push/PR-triggered runs simply queue (up to
24h) while the runner is offline and start when it returns — GitHub has no
automatic runner failover.

Registration is PER-REPO on personal accounts. Wiring a NEW repo:

1. `bash scripts/add-runner.sh <repo-name>` (in this repo) — ~60 seconds.
2. Copy the caller template above (it already carries the runner default).

The workflow skips its Tailscale join step on self-hosted runners
automatically (the host is already a tailnet member). Full operations doc:
"Self-hosted runner (Hetzner)" in
`Infra/Runbooks/Deployment/CI-CD-Deploy-Workflow.md`.

**Required secrets in caller repo:**

| Secret | Source |
|---|---|
| `DOKPLOY_API_TOKEN` | global Dokploy API key (see `Infra/Vault/Secrets.md`) |
| `DOKPLOY_COMPOSE_ID` | per-app compose ID |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client (`tag:ci`) |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret |

**`/ready` endpoint contract** — every custom app MUST implement:

```
GET /ready  ->  200 JSON
{
  "status": "ready",
  "version": "<from package.json>",
  "revision": "<APP_REVISION env, baked at build time>",
  "timestamp": "<ISO8601>"
}
```

The reusable workflow passes `APP_VERSION` and `APP_REVISION` as docker
build-args, so the app's Dockerfile must declare them and pass them to
the runtime as ENV:

```dockerfile
ARG APP_VERSION=unknown
ARG APP_REVISION=unknown
ENV APP_VERSION=$APP_VERSION \
    APP_REVISION=$APP_REVISION
```

**Why `--resolve` is in the verify step** — public DNS for
`*.innovspatial.app` resolves to Contabo's public IP, where the
`DOCKER-USER` iptables chain DROPs non-Tailscale, non-office source
IPs. The GHA runner connects to Tailscale (`tag:ci`) but its public
egress is its own GitHub-hosted IP, not its Tailscale IP. Forcing
curl to dial Contabo's Tailscale IP (`100.83.140.7`) while keeping
the original Host header bypasses the public-DNS path: Traefik routes
by Host header, the cert validates by SNI, DOCKER-USER allows the
Tailscale source.

## See also

- Full pattern documentation: `Infra/Runbooks/Deployment/CI-CD-Deploy-Workflow.md`
- Server inventory (Tailscale IPs, target servers): `Infra/Vault/Servers-Devices.md`
- Dokploy API reference: `Infra/Runbooks/APIs/Dokploy-API.md`
