# Prefect

Prefect owns a reusable Host carrier and a thin Workload contract so a solo operator can ship many small projects, experiments, and MVPs without repeating platform work, paying for managed infrastructure too early, or becoming dependent on a PaaS that is costly to leave. It removes unproductive friction (platform TLS, repeated provisioning) and keeps productive friction (declaring how containers run). Host capacity changes should remain routine and low-disruption; scale vertically while the shared Host remains sufficient, then graduate a Workload to dedicated infrastructure.

## Language

**Prefect**:
The name of this project: infrastructure-as-code for the platform other projects run on (Hosts, networks, environments) — without deciding what those projects are. From Latin *praefectus*: an appointed authority placed over a defined sphere under delegated power, not ownership of the work’s purpose.
_Avoid_: Infra, platform repo, DevOps project (when you mean this project)

**Stack**:
A Terraform root module that owns a cohesive slice of infrastructure for one provider or concern. Today the only stack is DigitalOcean (past Bootstrap: it manages Hosts and related network resources). One Stack definition is Applied separately per Environment.
_Avoid_: Project, workspace (Terraform State slices are an implementation detail — see Environment); Environment (when you mean the module itself rather than an instance)

**Environment**:
A namespaced instance of a Stack under one provider account: its own State and its own account-unique cloud names (including Cloud Project, Host, Host Volume, Domain, tags, Firewall, SSH key). Identified by an open-ended operator-chosen slug (e.g. `test`, `prod`, `dev`, `staging` — no fixed enum). When no Environment is explicitly selected, the operator is on the **test** Environment. In operator tooling, `test` and `default` refer to that same Environment (`default` is the only alias). Prefect operator CLI is safe by default: every operator entrypoint accepts an Environment parameter and affects **test** unless another Environment is explicitly specified. A `prod` Environment is optional — created only when needed. Distinct from the provider Cloud Project’s metadata `environment` field (Production / Staging / …), which is billing/UI labeling only.
_Avoid_: Workspace, stage, stack instance, Terraform workspace (when you mean this concept); environment variable / process environment (shell); Cloud Project `environment` field

**Cloud Project**:
A provider-side folder that groups billable resources for UI and billing. Distinct from Prefect, Stack, and Environment. Each Environment gets its own Cloud Project (namespaced by Environment slug). Resources that cannot be assigned (Firewall, tags, SSH keys) stay Stack-managed only.
_Avoid_: Project (bare), DO project (when speaking in domain language)

**Bootstrap**:
The initial content of a Stack: provider configuration, version pins, authentication wiring, and state backend — deliberately without managed cloud resources. Bootstrap for the DigitalOcean Stack is complete once Hosts (and their network companions) are managed in State.
_Avoid_: Scaffold, skeleton, hello-world

**State**:
The Terraform record of what a Stack currently manages. For Bootstrap, State is local to the operator's machine.
_Avoid_: Backend, tfstate (implementation jargon for the concept itself)

**Credential**:
A secret used to authenticate to a cloud provider. Supplied via the environment (never committed); for DigitalOcean that is the API token in `DIGITALOCEAN_TOKEN`.
_Avoid_: Key, secret, password (when you mean the provider API token)

**Host**:
A virtual machine managed by a Stack. The first Host in this Stack is a public web host (HTTP/HTTPS plus SSH).
_Avoid_: Droplet, instance, VM, box, server (when you mean this compute resource)

**Host Image**:
The provider distribution image the Stack pins for a Host (today: Ubuntu 26.04 x64). Changing it recreates the Host.
_Avoid_: Droplet image, OS slug, AMI (when you mean this concept)

**Initial Host Provisioning**:
One-shot Host setup applied when the Host is created (delivered via the provider’s user-data / cloud-init). Prepares the Host as a carrier for Components (engine, Prefect User, SSH listen port, port floor, Host Volume mount) but does not run Component Setup and does not install Workloads. Not ongoing Host management and not Stack Bootstrap.
_Avoid_: User Data, cloud-init, userdata (when you mean this concept); provisioning (bare — ambiguous with Stack apply)

**Carrier ready**:
Host-local gate: wait until Initial Host Provisioning outcomes required for Component Setup hold on a public Host (IHP finished, port floor 80, Prefect User present, Host Volume mounted at `/var/lib/prefect`). Used by ensure-components and Acceptance Tests before asserting finer capability slices. Delivery mechanics (cloud-init) stay inside the gate’s implementation.
_Avoid_: cloud-init ready, provisioned (bare), ready (bare)

**Host diagnostics**:
An operator pull of Host-local diagnostic artifacts for an Environment (named bundles of files and small command snapshots) for local inspection. Not Carrier ready, not an Acceptance Test, and not ongoing Host management.
_Avoid_: logs (bare), cloud-init logs (when you mean this operator capability); debug dump, support bundle (when you mean this Prefect operation)

**Reserved IP**:
A stable public IPv4 address owned by the Stack and assigned to a Host. It survives Host rebuilds and Park; Teardown removes it with the rest of the Stack. The Host's own public IP does not survive rebuilds.
_Avoid_: Floating IP, static IP, elastic IP (when you mean this address resource)

**Domain**:
The Stack-managed DNS Durable for an Environment: the provider zone and the Stack-authored records under it. A records to the Environment’s Reserved IP are required for each declared name (apex or subdomain); a Domain may carry more Stack-authored records over time. Certificate material for those names is Domain-scoped — a Workload may use a Domain’s names via Routes; it does not own the Domain or its certificates. An Environment may have zero or more Domains. Park keeps it; Apply reattaches it; Teardown removes it; assigned to the Environment’s Cloud Project. Not Workload ownership of names.
_Avoid_: DNS zone, zone file, domain name (bare), subdomain (when you mean this Durable or part of it); Workload-owned certificate; Manifest hostname claim

**Host Volume**:
A Stack-owned block volume attached to a public Host for durable data that must survive Host rebuilds and Park (Teardown removes it with the rest of the Stack). Mandatory on public Hosts (one per Host for now). The mount root stays root-owned; everything under it (Component source trees, Component data such as Edge Domain fronts, Workload Routes, certificates, and ACME HTTP-01 webroot, and later other Prefect/Workload paths) is owned by the Prefect User so rootless Quadlets and Workload Setup can use it. Quadlet units stay under the Prefect User’s home. Not per-Workload volumes.
_Avoid_: Volume (bare), disk, block storage, persistent volume, DO volume (when you mean this Prefect resource)

**Firewall**:
A provider-enforced network filter attached to Hosts. Inbound default deny (only SSH, HTTP, HTTPS, and ICMP allowed); outbound unrestricted. The Stack does not manage a host-level firewall. Attachment is by Role Tag, not by Host ID alone.
_Avoid_: Security group, ufw, iptables, cloud firewall (product name when you mean this concept)

**Prefect Tag**:
A provider tag that marks taggable resources as belonging to Prefect (name derived per Environment, e.g. test: `prefect-test`). Applied to every Prefect Host. Not all Stack resources are taggable (Firewall, Reserved IP, and SSH keys are not).
_Avoid_: Office Tag, Shared tag, prefect tag (when you mean this concept); Role Tag

**Role Tag**:
A provider tag that selects Hosts for a policy such as a Firewall (public web for test: `prefect-test-public-web`). Orthogonal to the Prefect Tag; a Host may carry both.
_Avoid_: Firewall tag (ambiguous — the Firewall targets the Role Tag; it is not itself tagged)

**Acceptance Test**:
An executable check of Applied Stack external behavior (does the live Stack match the intended contract?). Requires an applied Stack (Host present) and asserts observable outcomes only — not Terraform internals or provider API shape. Non-destructive to Stack lifecycle: must not Park or Teardown. Follows the default-safe operator CLI Environment rule (ADR-0019).
_Avoid_: Verify script, observability check, smoke test, integration test, Lifecycle Test (when you mean this concept)

**Lifecycle Test**:
An executable check of Stack lifecycle operations that deliberately remove or restore Stack presence (Park, Apply-after-Park, Teardown). Separate from Acceptance Tests; opt-in; may leave the Stack Parked or empty. Not part of `./test.sh`. Follows the same default-safe operator CLI Environment rule as other entrypoints (ADR-0019) — defaults to **test**; other Environments only with explicit `--env`.
_Avoid_: Acceptance Test, destroy test, integration test (when you mean this concept)

**Apply**:
The operation that converges a Stack to Applied from Applied, Parked, or a supported partially failed lifecycle operation. Repeating Apply is the normal recovery path and ends with an empty plan; may Adopt allowlisted facts as part of its normal convergence. External drift, unmanaged collisions, Adopt ambiguity, and provider/account hard failures remain explicit blockers.
_Avoid_: up, provision, terraform apply (when you mean this operation)

**Adopt**:
The binding of an already-existing provider fact into State under the Environment’s known Stack-owned identity. Adopt starts with exact-match preflight; binding may complete there or during the ensuing normal lifecycle convergence when an already-correct relationship cannot be bound earlier. Apply may Adopt allowlisted Durables and known Recreatable relationships; Park and Teardown may Adopt allowlisted Durables and Durable relationships only. None is a separate operator command. Scope is identity-stable Durables (Domain, Host Volume, Cloud Project, and their Durable memberships) and — for Apply only — known Recreatable relationships whose endpoints are already known. Ambiguity, wrong endpoint, identity conflict, or a binding that would move or rewrite the provider fact fails closed. Not discovery of an unbound Host by name, and not an orphan Reserved IP address (no Environment key without State).
_Avoid_: import, terraform import, State surgery, auto-import (when you mean this concept)

**Applied**:
The stable Stack condition in which every configured Durable and Recreatable is present and converged.
_Avoid_: running, up, active

**Durable**:
A Stack-managed resource or relationship that Park preserves and Apply keeps converged. Today this includes the Reserved IP, Host Volume, Domain, Cloud Project, and the relationships that keep those resources assigned while Parked.
_Avoid_: persistent resource, stateful resource (when you mean this Park/Apply set)

**Recreatable**:
A Stack-managed resource or relationship that Park removes and Apply recreates without preserving its identity or data. Today this includes the Host and its Applied-only companions and relationships.
_Avoid_: non-durable, ephemeral resource, disposable resource

**Additive Stack Change**:
A configuration change that adds resource instances or relationships while leaving every existing managed identity and desired attribute unchanged.
_Avoid_: non-destructive change, additive update (bare)

**Park**:
The operation that converges a Stack to Parked from Applied, Parked, or a supported partially failed lifecycle operation. May Adopt allowlisted Durables as part of its normal convergence. A cost convenience for development and other non-production Environments; Durables continue to bill while Parked.
_Avoid_: soft destroy, soft teardown, down, halt, suspend, Destroy (ambiguous — say Park or Teardown)

**Parked**:
The stable Stack condition in which every configured Durable is present and converged and every Recreatable is absent.
_Avoid_: stopped, down, inactive

**Teardown**:
Permanently remove every resource the Stack currently manages, including Durables, leaving State empty. May Adopt allowlisted Durables first so Environment-keyed orphans are included in the wipe. Stack configuration stays in the repository and can be Applied again. Explicit full wipe when Durable billing should stop — not the idle path for non-production (that is Park).
_Avoid_: Destroy, wipe, delete resources, terraform destroy (when you mean this full removal); Purge (Workload-only)

**Component**:
An installable unit of Prefect’s mandatory Host shape, owned as a directory under `prefect/` with its own idempotent Component Setup. Today’s Components are the Service Network and the Edge. Workloads are not Components.
_Avoid_: Package, unit, service, module (when you mean this installable Prefect piece)

**Component Setup**:
The idempotent, declarative Host-side application of one Component’s desired state. After a successful Component Setup, that Component is in the correct state. Reads that Component’s source tree from the Host Volume (and may source shared Host-local helpers from `/var/lib/prefect/components/lib/`); runs on the Host only; does not discover the Stack, SSH, or copy itself onto the Host. Used for first bring-up after Initial Host Provisioning and for later re-runs without Host recreation.
_Avoid_: Setup (bare), install, deploy, provision, Workload Setup (when you mean this Component action)

**Workload Setup**:
The idempotent, declarative Host-side application of one Workload’s Intent from its Manifest: sync operator-authored Quadlets from the Workload definition tree’s `quadlets/` into the Prefect User unit directory under their authored basenames and apply them per Intent (**run** reconciles install/start and drops units removed from SoT; **stop** / **trash** stop those units — unit files retained until Purge), and reconcile of that Workload’s operator-authored Routes into the Edge routes directory for Domain fronts to include (**run** installs; **stop** / **trash** removes that Workload’s installed Routes) with an Edge reload when the installed set changes. Missing or empty `quadlets/` or `routes/` is valid (zero of either). Refuses to overwrite a unit basename already present in the unit directory unless this Workload’s stored `quadlets/` already owns it. Does not generate Route or Quadlet content from the Manifest; does not write Domain fronts. Distinct from Component Setup; not part of ensuring Components. Distinct from Purge.
_Avoid_: Setup (bare), Component Setup, install, deploy, Purge (when you mean this Workload action)

**Edge**:
The mandatory public HTTP/HTTPS front door on a public Host. A Prefect Component (not optional). Sole publisher of Host ports 80/443; terminates TLS using Domain-scoped certificates; owns on-demand ACME as the issuance mechanism. For each want-list FQDN it publishes a Domain front; Workloads attach via operator-authored Routes included into those fronts. ACME’s want-list is the explicit FQDN set from the Environment’s Domain assignment (apex + `names`); ensure-components installs that want-list and the Domain fronts on the Host; ACME does not generate or mutate Domain fronts or Workload Routes. On :80, only ACME challenges and HTTPS redirects — never Workload cleartext.
_Avoid_: Reverse proxy, ingress, gateway, nginx (when you mean this Prefect role — nginx is today’s implementation)

**Domain front**:
Edge-owned per-FQDN drop-in for one want-list name: the HTTPS `server` that terminates TLS for that Domain name and includes matching Workload Routes. Publishes Edge baseline `/healthcheck` and the per-name `:80`→HTTPS redirect without a Workload Route. Lives under Edge data `domains/` (not Workload `routes/`); reconciled by ensure-components with the want-list; never Workload-owned and never ACME-mutated.
_Avoid_: Domain Route, Edge Route, vhost (when you mean this Edge-owned front); Workload Route

**Workload**:
An optional containerized service that runs on a Host. Identified by the basename of its Workload definition tree (the directory that holds the Manifest), not by a Manifest field. Not part of Prefect’s mandatory Host shape, not a Component, and never installed during Initial Host Provisioning; typically reached only via the Edge, not by publishing 80/443 itself.
_Avoid_: App, service, container, backend (when you mean this concept)

**Workload Manifest**:
A Workload-owned declaration that is the source of truth for that Workload’s Intent (**run**, **stop**, or **trash**), with an optional human-only `description` ignored by all automation. It does not name the Workload, claim DNS names, feed ACME, or carry runtime/Quadlet config; operator-authored Routes and Quadlets live in the Workload definition tree alongside the Manifest (`routes/` and `quadlets/` siblings).
_Avoid_: Manifest (bare), spec, compose file, workload config (when you mean this declaration)

**Workload Intent**:
The Manifest’s post–Workload Setup expectation — what must be true after Setup succeeds; never Host status or a report of what is currently on the server. **run** (Quadlets up; that Workload’s operator-authored Routes installed for Domain fronts to include when present — zero Route files is valid; HTTP semantics are whatever those fragments declare inside the Domain front, not Prefect-generated shells; reachability is not a Setup success criterion), **stop** (no Quadlets; that Workload’s Routes are not installed, so the Domain front serves only its Edge baseline — today `/healthcheck` and miss behaviour as configured there — not a Prefect-managed 503), or **trash** (eligible for Purge; associated Workload data retained until Purge).
_Avoid_: Workload Desired State, desired state, running, stopped, trashed, active, disabled, remove, status, phase, current state (when you mean this Manifest field)

**Purge**:
The operation that permanently removes every Workload whose Intent is **trash** and its Workload-associated data (that Workload’s installed Routes, Host Volume Workload tree including stored `routes/` and `quadlets/` SoT, and Prefect User unit files whose basenames appear in that Workload’s `quadlets/`). Does not delete Domains or Domain-scoped certificate material. Does not affect Workloads whose Intent is **run** or **stop**.
_Avoid_: Teardown (Stack-level), Destroy, delete, cleanup, gc (when you mean this Workload operation)

**Service Network**:
The private container network on a Host that the Edge and Workloads join so they can reach each other by name. Owned by Prefect as its own Component (not by the Edge). Distinct from the provider Firewall.
_Avoid_: Podman network, bridge, CNI (implementation); network (bare — ambiguous with Firewall / provider networking)

**Route**:
Operator-authored Edge config (native format, server-context only) whose source of truth is `workloads/<name>/routes/` on the Host Volume. Basename is the FQDN of the Domain front it attaches to (`<fqdn>.conf`); Workload Setup installs it as `<name>--<fqdn>.conf` into the Edge routes directory for that Domain front to include (**run** only; **stop** / **trash** remove that Workload’s installed files). Basename must match a want-list FQDN or Setup fails closed. Missing `routes/` is valid (zero Routes). Not a full TLS `server` block, not projected from the Manifest, and not a hostname claim field — the FQDN is the filename. Edge ACME does not generate or mutate Routes; Domain fronts and empty stubs remain Edge/Component-owned; Workload Routes must not be cleared by Component Setup.
_Avoid_: Vhost, upstream, location block, snippet, server block (when you mean this Workload attachment); Domain front; projected Route, generated shell, interior (removed Prefect Route features)

**Prefect User**:
The Host login account that runs Prefect’s rootless user Quadlets (linger enabled so user systemd stays up without an interactive session). Created by Initial Host Provisioning on public Hosts — account and linger only, not Quadlet units.
_Avoid_: edge user, podman user, service account (when you mean this Host account)
