# Antigravity CLI (`agy`) Sandbox Kit

Docker Sandboxes **v3 workload kit** for running [Google's Antigravity CLI](https://antigravity.google/product/antigravity-cli) (`agy`) in YOLO mode inside an isolated sandbox. The repository also ships an `agy-mixin` variant for adding the CLI to another v3 workload.

The kit installs the official `agy` binary, starts it with `--dangerously-skip-permissions --mode=accept-edits`, and forces its headless OAuth flow so authentication works without a local browser. Antigravity can therefore run commands and edit files without its own approval prompts; the Docker sandbox remains the security boundary.

OAuth is managed by Docker Sandboxes' host-side credential proxy. Sign in once on the first sandbox created from the kit, and later Antigravity sandboxes can reuse that login without exposing the real access or refresh token inside their VMs.

## Quick start

```bash
sbx run git+https://github.com/shelajev/agy-sbx-kit.git .
```

After publishing the v3 artifact, run it from Docker Hub:

```bash
sbx run docker.io/olegselajev241/agy-sbx-kit:latest .
```

The existing `latest` tag may still point to the legacy v2 artifact until the
v3 release workflow has completed; use the Git source form while reviewing
this migration.

For reproducible automation, pin the Git source to a full commit SHA or use the
Docker Hub digest printed by `sbx kit push` instead of a moving reference.

A commit-pinned Git invocation looks like this:

```bash
sbx run 'git+https://github.com/shelajev/agy-sbx-kit.git#ref=<40-character-commit-sha>' .
```

On the first run, Docker Sandboxes asks you to approve the kit's `antigravity` OAuth credential binding. Then `agy` prints a Google OAuth URL. Open it in a browser on your laptop, complete the Google sign-in, then paste the callback URL (or code) back into the sandbox terminal. The host credential proxy captures and stores that OAuth session. New sandboxes created from this kit can then start already authenticated.

## Named sandbox

For a sandbox you can reattach to later:

```bash
sbx create --name agy-current \
  git+https://github.com/shelajev/agy-sbx-kit.git .

sbx run --name agy-current
```

Current `sbx` versions remember the workload kit on the named sandbox.

## Mixin variant

To add Antigravity to another v3 workload without replacing that workload's entrypoint, compose `agy-mixin` and run `agy` from the resulting environment:

```bash
sbx run <V3-WORKLOAD> \
  --kit 'git+https://github.com/shelajev/agy-sbx-kit.git#dir=agy-mixin' .
```

Kits v3 cannot be composed with v1 or v2 kits. The workload and every mixin in one sandbox must all use v3.

## How auth works

`agy`'s local auth path tries to open a browser and listen on `localhost:36742` for the OAuth callback — neither of which makes sense from inside a sandbox. The kit sets `SSH_CONNECTION` so `agy` detects a "remote" environment and switches to its copy/paste fallback:

1. CLI prints an `accounts.google.com` authorization URL.
2. You open it in any local browser, sign in, approve.
3. Google redirects you to a `http://localhost:36742/oauth-callback?code=...` URL that won't load — that's expected.
4. Copy the full URL from your browser's address bar and paste it back at the sandbox prompt.

Inside the sandbox, Antigravity still sees `~/.gemini/antigravity-cli/antigravity-oauth-token`, but it contains proxy-managed sentinel values rather than your real access and refresh tokens. The real credentials remain in Docker Sandboxes' host credential store, where they can be reused by other sandboxes created from the same kit.

An existing Antigravity token created before this kit declared OAuth cannot be imported automatically. After updating the kit, complete one fresh login so the proxy can capture and manage the token exchange.

To log out from inside the sandbox, run `/logout` at the `agy` prompt.

## How it works

- **Image build:** `agy.dockerfile` runs the official installer and packages the resulting CLI into the kit artifact. Sandbox creation no longer downloads executable content.
- **Entrypoint:** `agy --dangerously-skip-permissions --mode=accept-edits` (the shell-docker image puts `~/.local/bin` on PATH). The first flag covers tool permission requests; the execution mode separately auto-approves file edits.
- **Lifecycle:** At sandbox creation, the kit seeds `~/.gemini/antigravity-cli/settings.json` with permissive tool, file, URL, MCP, and artifact-review settings. The file is created only when missing, so later user changes are preserved. The command-line flags are the per-session overrides.
- **Authentication:** Docker Sandboxes intercepts the Google token exchange and writes proxy-managed sentinel credentials at Antigravity's expected token path. The host holds and refreshes the real tokens for reuse across sandboxes.
- **Persistence:** Inherited from `sbx` defaults — conversations and other sandbox-local state survive restarts, while authentication is shared through the host credential proxy.

### Upgrading an existing sandbox from v1.0.0

V1.0.1 removes the obsolete `unsandboxed(*)` permission that newer Antigravity
versions warn about. The kit deliberately preserves an existing settings file,
so an already-created sandbox may retain that line. Remove it with
`/permissions`, edit `~/.gemini/antigravity-cli/settings.json` inside the
sandbox, or recreate the sandbox. `command(*)` already grants command
execution; removing `unsandboxed(*)` does not reduce the kit's intended YOLO
behavior.
- **Self-update:** `agy` self-updates in the background; the updater domain is allowlisted.

## Security model

YOLO mode intentionally disables Antigravity's interactive tool approvals. Use this kit only where the Docker sandbox is the intended security boundary. The agent can freely change files mounted into its workspace and can reach the domains allowed by the kit's network policy, but it remains isolated from the rest of the host by Docker Sandboxes.

## Network policy

The kit allows only:

- `antigravity.google` — installer and docs
- `antigravity-unleash.goog` — Antigravity feature flags
- `antigravity-cli-auto-updater-974169037036.us-central1.run.app` — release manifests and binaries (also used for self-update)
- `accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com` — Google OAuth
- `cloudaicompanion.googleapis.com`, `cloudcode-pa.googleapis.com`, `daily-cloudcode-pa.googleapis.com`, `generativelanguage.googleapis.com` — Antigravity / Gemini Code Assist APIs

If your workflow needs to reach package registries (npm, PyPI, crates.io, Go modules, etc.) or your own services, fork the kit and extend the runtime allowlist in the `com.docker.sandbox/network-policy@1` capability in `agy.yaml`.

## Smoke test

For `sbx exec`, close or pipe stdin so the CLI does not block waiting for input:

```bash
sbx exec agy-current -- sh -lc 'agy --help < /dev/null'
```

You should see the standard `agy` help text. Hitting the actual model requires an authenticated session, so the first interactive run across this kit's sandboxes still needs the OAuth paste-back.

## Local clone

If you clone this repo, `run.sh` runs a named sandbox using the local kit path:

```bash
./run.sh agy-current
```

Use any sandbox name as the first argument:

```bash
./run.sh my-sandbox
```

## Build and validate

Kits v3 build as ordinary OCI images through the sandbox-kit frontend:

```bash
docker buildx build . -f agy.yaml -t agy-sbx-kit:1.0.1 --load
docker buildx build agy-mixin -f agy-mixin/agy-mixin.yaml \
  -t agy-sbx-kit-mixin:1.0.1 --load
```

In a TLS-inspecting network, pass the organization's CA bundle as an ephemeral
BuildKit secret with `--secret id=proxy_ca,src=/path/to/ca-bundle.crt`. The
certificate is available only to the installer step and is not stored in the
resulting image.

For conformance testing without publishing, export an OCI layout and run `kit-tck`:

```bash
docker buildx build . -f agy.yaml -t agy-sbx-kit:1.0.1 \
  --output type=oci,dest=/tmp/agy-kit-layout,tar=false
kit-tck validate --layout /tmp/agy-kit-layout 1.0.1
```

Publish workload and mixin as separate v3 artifacts; do not use the legacy `sbx kit push` packaging flow:

```bash
docker buildx build . -f agy.yaml --platform linux/amd64,linux/arm64 \
  -t docker.io/olegselajev241/agy-sbx-kit:1.0.1 \
  -t docker.io/olegselajev241/agy-sbx-kit:latest --push

docker buildx build agy-mixin -f agy-mixin/agy-mixin.yaml \
  --platform linux/amd64,linux/arm64 \
  -t docker.io/olegselajev241/agy-sbx-kit-mixin:1.0.1 \
  -t docker.io/olegselajev241/agy-sbx-kit-mixin:latest --push
```

## License

Apache 2.0. See [LICENSE](LICENSE).
