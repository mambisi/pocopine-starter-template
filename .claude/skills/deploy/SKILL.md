---
name: deploy
description: >-
  Use when deploying a pocopine full-stack or static app to Fly.io, Railway, Render, or other hosts using the RFC 080 deploy contract
---

## What this is

The pocopine deployment system is a Heroku-style process model (RFC 080) that decouples app config from host-specific infrastructure. Write one portable `[deploy]` block in `Pocopine.toml`; adapters translate it to Fly/Railway/Render native configs. Switching hosts is `--target fly` → `--target railway`, nothing else.

## When to use

- **Configuring deployments**: authoring or editing `[deploy]` blocks in `Pocopine.toml`
- **Running deploy commands**: `pocopine deploy --target <host>`, `pocopine deploy auth`, `pocopine deploy doctor`
- **Understanding process graphs**: declaring `web` and `worker` processes for jobs + collab
- **Troubleshooting deploys**: checking constraints, validating Pocopine.toml, probing host API versions
- **Switching between hosts**: understanding why an app that works on Railway might need changes for Render

## Key API / syntax

### `Pocopine.toml [deploy]` block

```toml
[deploy]
mode = "fullstack"              # "fullstack" | "static"

[deploy.processes.web]
bin         = "server"          # cargo bin name (required)
port        = 8080              # public HTTP port
healthcheck = "/healthz"        # optional HTTP health endpoint
scale       = { min = 1, max = 5 }  # replicas (min/max)
public      = true              # default true if port set; false hides from ingress

[deploy.processes.worker]       # optional; background job processor
bin   = "worker"
scale = { min = 1, max = 3 }

[deploy.services]               # declare required backing services
postgres = { required = true }  # auto-inferred if using pocopine storage or collab
redis    = { required = true }  # auto-inferred if jobs or collab present

[deploy.env]
DATABASE_URL = { from = "secret" }  # pulled from process env at deploy time
REDIS_URL    = { from = "secret" }
LOG_LEVEL    = "info"               # literal value baked into image

[deploy.render]                 # host-specific overrides (optional)
owner_id = "tea-..."            # Render workspace ID
plan     = "starter"            # pricing plan
```

### CLI commands

```bash
pocopine deploy                 # prompt for target; build + deploy
pocopine deploy --target fly    # name the host explicitly
pocopine deploy --dry-run       # print what would happen
pocopine deploy --skip-build    # reuse existing image (CI pattern)
pocopine deploy --prod          # production environment (suffixes app name)

pocopine deploy auth railway    # one-time: store API token
pocopine deploy auth --list     # show configured hosts
pocopine deploy doctor          # validate Pocopine.toml, probe host APIs

pocopine build                  # local Rust build; output to target/ + dist/
pocopine build --container      # build inside pocopine/build container (reproducible)
```

### Trait (`DeployAdapter`)

Every adapter (railway.rs, render.rs, fly.rs) implements:

- **`name() -> &str`** — adapter identifier (e.g., `"railway"`)
- **`mode() -> AdapterMode`** — `Static`, `Fullstack`, or `Both`
- **`tested_against() -> semver::VersionReq`** — host API versions this adapter knows
- **`detect_constraints(spec) -> Vec<Constraint>`** — pure validation; `Refuse` halts, `Warn`/`Hint` advise
- **`render_config(spec, out)`** — pure; writes Dockerfile, railway.json, render.yaml to staging dir
- **`build_artefact(spec) -> Artefact`** — I/O; invokes `docker build`, returns OCI image tag
- **`deploy(spec, artefact) -> DeployOutcome`** — I/O; calls host API, pushes image, triggers deploy
- **`post_deploy_hint(spec, outcome) -> Vec<Hint>`** — pure; returns one-time setup commands
- **`status(spec) -> Vec<ProcessStatus>`** — I/O; query current deploy state per process

### Build artefacts

| Mode | Output | Runtime entrypoint |
|---|---|---|
| `static` | `dist/` directory (HTML, JS, CSS, wasm) | host serves files; no app code |
| `fullstack` | OCI image (multi-stage Rust build → distroless) | `pocopine-launcher <process>` (PID 1 shim) |

## Examples

### Example 1: Two-process job app (from RFC 080 §4.1)

```toml
# Pocopine.toml
[deploy]
mode = "fullstack"

[deploy.processes.web]
bin         = "server"
port        = 8080
healthcheck = "/healthz"
scale       = { min = 1, max = 5 }

[deploy.processes.worker]
bin   = "worker"
scale = { min = 1, max = 3 }

[deploy.services]
postgres = { required = true }
redis    = { required = true }

[deploy.env]
DATABASE_URL = { from = "secret" }
REDIS_URL    = { from = "secret" }
LOG_LEVEL    = "info"
```

Deploy to three different hosts with identical config:
```bash
pocopine deploy --target fly       # Fly machines + Fly Postgres + Upstash Redis
pocopine deploy --target railway   # Railway services + managed Postgres + managed Redis
pocopine deploy --target render    # Render services + managed Postgres + managed Redis
```

### Example 2: Railway adapter snippet (from crates/pocopine-deploy-railway/src/lib.rs)

The `detect_constraints` method gates deployment before building:

```rust
fn detect_constraints(&self, spec: &DeploySpec) -> Vec<Constraint> {
    let mut out = Vec::new();
    
    if spec.mode == Mode::Static {
        out.push(Constraint::Refuse(
            "railway adapter is fullstack-only; for static-site mode use `cf-pages`".into(),
        ));
    }
    
    // Scale: Railway holds services warm, so scale.min = 0 floors to 1
    for (name, proc) in spec.processes() {
        if proc.scale.min == 0 {
            out.push(Constraint::Warn(format!(
                "process `{name}` scale.min = 0; flooring to 1 (Railway holds services warm)"
            )));
        }
    }
    
    out
}
```

### Example 3: pocopine-launcher (from crates/pocopine-launcher/src/main.rs)

The launcher resolves process names to binaries at runtime:

```rust
fn main() -> ! {
    let proc = std::env::args().nth(1)
        .or_else(|| std::env::var("POCOPINE_PROCESS").ok())
        .expect("usage: pocopine-launcher <process>");
    
    let bin = match proc.as_str() {
        "web"    => "/usr/local/bin/server",    // from [deploy.processes.web] bin = "server"
        "worker" => "/usr/local/bin/worker",    // from [deploy.processes.worker] bin = "worker"
        other    => panic!("unknown process: {other}"),
    };
    
    exec::Command::new(bin).args(std::env::args().skip(2)).exec();
}
```

Each host invokes: `pocopine-launcher web` (for web replicas), `pocopine-launcher worker` (for background workers).

## Gotchas

1. **No vendor code in user crates**: unlike RFC 041 (Shuttle), the deploy artefact is an OCI image + portable spec, not vendor-shaped. Never use `#[shuttle_*]` macros or host-specific entrypoints.

2. **Redis is inferred, not optional**: if the build contains `#[job]` macros or `pocopine-collab` is in Cargo.toml, `redis` becomes `required = true` automatically. Override with `redis = { required = false }` only if bringing your own Redis.

3. **Collab is not a separate process**: the WebSocket handler for collaborative editing rides inside the `web` process (it's a mounted axum route). Do not declare `[deploy.processes.collab]`.

4. **Secrets must be set in the deploy shell**: `[deploy.env] KEY = { from = "secret" }` means the adapter expects `$KEY` to be set in the invoking process. At deploy time, the adapter reads it and pushes it to the host's secrets store. Unset secrets cause a `Constraint::Refuse` before building.

5. **Static mode rejects multiple processes**: `mode = "static"` forbids anything except an optional `[deploy.processes.web]` with no `bin` (interpreted as "serve dist/"). Jobs and workers are fullstack-only.

6. **Scale-to-zero semantics vary by host**: Fly supports `scale.min = 0`; Railway and Render floor it to 1 with a warning (they keep services warm). Check the adapter's `detect_constraints` to see what your target allows.

7. **Process names must normalize safely**: `web`, `worker`, `api-v2`, and `my_scheduler` all work. Names are normalized to env vars: `my-api` → `POCOPINE_PROC_MY_API`. Two process names that normalize to the same env var cause a `Refuse` constraint.

8. **Host-override blocks are optional**: `[deploy.fly]`, `[deploy.railway]`, `[deploy.render]` are for host-specific tweaks (regions, plans, workspace IDs). The portable spec alone is sufficient for basic deploys.

9. **`--container` is opt-in**: `pocopine build` uses your local Rust toolchain by default (fast iteration). `--container` builds inside `ghcr.io/pocopine/build:<version>` for reproducible CI builds. Docker is only required if you use `--container`.

10. **Generated files are overwritten**: Dockerfile, `render.yaml`, `railway.json`, and `fly.toml` are regenerated every deploy from Pocopine.toml. Hand-edits are lost. Use `[deploy.<host>]` overrides for permanent tweaks, or set `generated = "freeze"` to stop regenerating and manage the file yourself.

## References

- **RFC 080**: `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-080-deploy-contract.md` — full specification (process graph, backing services, adapter trait, build container, CLI)
- **Crate**: `crates/pocopine-deploy/` — core trait, spec parsing, shared helpers
- **Adapters**:
  - `crates/pocopine-deploy-railway/src/lib.rs` — Railway (GraphQL API, project/service/plugin mutations)
  - `crates/pocopine-deploy-render/src/lib.rs` — Render (REST API, web_service/background_worker types)
  - `crates/pocopine-deploy-fly/` — Fly.io (existing Phase 1 adapter; see RFC §10)
- **Launcher**: `crates/pocopine-launcher/src/main.rs` — process dispatch via `POCOPINE_PROC_<NAME>` env vars
- **Shared**: `crates/pocopine-deploy/src/common.rs` — Dockerfile template rendering, `.dockerignore`, env collision detection
- **CLI**: `pocopine-cli`'s `deploy` command module orchestrates the pipeline (validate → render_config → build_artefact → deploy → post_deploy_hint)
- **Config resolution**: `crates/pocopine-deploy/src/config.rs` — three-tier lookup (env → Cargo.toml → ~/.pocopine/config.toml)
- **Credentials**: `crates/pocopine-deploy/src/credentials.rs` — token storage in ~/.pocopine/credentials.toml (0600 perms)
