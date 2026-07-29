# Thin Workload Manifest (intent + description only)

After operator-owned Routes (ADR-0022) and Domain-driven ACME (ADR-0023), the Manifest was still thick: required `name` / `upstream`, and Workload Setup invented a default nginx Quadlet from `upstream`. That contradicted a minimal Prefect-specific surface and “no hidden Workload runtime defaults.” The Manifest is now only required `intent` plus optional human-only `description` (ignored by automation); strict allowlist — any other key fails Setup. Workload identity is the basename of the definition-tree directory that holds the Manifest. Operator-authored Quadlets live in sibling `quadlets/` (parallel to `routes/`); missing/empty is valid. Setup installs units under authored basenames into the Platform User unit directory, stores SoT on the Host Volume, reconciles on Intent **run**, stops units on **stop** / **trash** (files until Purge), and refuses to overwrite any existing unit basename unless this Workload’s stored `quadlets/` already owns it. Purge deletes Intent-**trash** Workloads’ tree (including `routes/` / `quadlets/` SoT), SoT-named units, and installed Routes — not Domains/certs. Manifest `source` (external fetch) is deferred. Clean break (ADR-0018): no dual-read of `name` / `upstream` / retired keys.

**Authored Quadlets + directory identity over Manifest `name`/`upstream` + Prefect-minted units:** keeps native Quadlet/nginx as the Workload languages and makes graduation “copy the definition tree.”

**Defer `source` over shipping a fetch field now:** local `routes/` + `quadlets/` are enough; avoid a mini package manager before a real operator need.

**Strict allowlist over ignore-unknown:** thick leftovers must fail loud, not half-apply.

**Authored unit basenames (no `<workload>--` prefix) over Route-style renaming:** units stay graduation-friendly; uniqueness is enforced by refusing foreign basenames in the unit directory.
