# Prefect

Infrastructure-as-code for Prefect. This repository holds Terraform stacks that provision and manage the cloud resources other projects run on.

## Language

**Prefect**:
The name of this project: infrastructure-as-code for the platform other projects run on (Hosts, networks, environments) — without deciding what those projects are. From Latin *praefectus*: an appointed authority placed over a defined sphere under delegated power, not ownership of the work’s purpose.
_Avoid_: Infra, platform repo, DevOps project (when you mean this project)

**Stack**:
A Terraform root module that owns a cohesive slice of infrastructure for one provider or concern. Today the only stack is DigitalOcean (past Bootstrap: it manages Hosts and related network resources). One Stack definition is Applied separately per Environment.
_Avoid_: Project, workspace (Terraform State slices are an implementation detail — see Environment); Environment (when you mean the module itself rather than an instance)

**Environment**:
A namespaced instance of a Stack under one provider account: its own State and its own account-unique cloud names (including Cloud Project, Host, Host Volume, tags, Firewall, SSH key). Identified by an open-ended operator-chosen slug (e.g. `test`, `prod`, `dev`, `staging` — no fixed enum). When no Environment is explicitly selected, the operator is on the **test** Environment. In operator tooling, `test` and `default` refer to that same Environment (`default` is the only alias). Prefect operator CLI is safe by default: every operator entrypoint accepts an Environment parameter and affects **test** unless another Environment is explicitly specified. A `prod` Environment is optional — created only when needed. Distinct from the provider Cloud Project’s metadata `environment` field (Production / Staging / …), which is billing/UI labeling only.
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
One-shot Host setup applied when the Host is created (delivered via the provider’s user-data / cloud-init). Prepares the Host as a carrier for Components (engine, Prefect User, port floor, Host Volume mount) but does not run Component Setup and does not install Workloads. Not ongoing Host management and not Stack Bootstrap.
_Avoid_: User Data, cloud-init, userdata (when you mean this concept); provisioning (bare — ambiguous with Stack apply)

**Carrier ready**:
Host-local gate: wait until Initial Host Provisioning outcomes required for Component Setup hold on a public Host (IHP finished, port floor 80, Prefect User present, Host Volume mounted at `/var/lib/prefect`). Used by ensure-components and Acceptance Tests before asserting finer capability slices. Delivery mechanics (cloud-init) stay inside the gate’s implementation.
_Avoid_: cloud-init ready, provisioned (bare), ready (bare)

**Reserved IP**:
A stable public IPv4 address owned by the Stack and assigned to a Host. It survives Host rebuilds and Park; Teardown removes it with the rest of the Stack. The Host's own public IP does not survive rebuilds.
_Avoid_: Floating IP, static IP, elastic IP (when you mean this address resource)

**Host Volume**:
A Stack-owned block volume attached to a public Host for durable data that must survive Host rebuilds and Park (Teardown removes it with the rest of the Stack). Mandatory on public Hosts (one per Host for now). The mount root stays root-owned; everything under it (Component source trees, Component data such as Edge Routes, certificates, and ACME HTTP-01 webroot, and later other Prefect/Workload paths) is owned by the Prefect User so rootless Quadlets and Workload Setup can use it. Quadlet units stay under the Prefect User’s home. Not per-Workload volumes.
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
Bring the Stack to its desired managed presence: create any missing resources and reattach existing Durables when they are already Stack-managed. Used after Park or Teardown, and for ordinary convergence. Fails fast if Durable assumptions do not hold (for example Durables missing from State or not reattachable as expected).
_Avoid_: up, provision, terraform apply (when you mean this operation)

**Durable**:
A Stack-managed cloud resource that Park keeps and Apply reattaches: today only the Reserved IP and the Host Volume. Not Hosts, Firewalls, tags, SSH keys, or the Cloud Project.
_Avoid_: persistent resource, stateful resource (when you mean this Park/Apply set)

**Park**:
Remove the Host and other non-durable Stack resources while keeping Durables Stack-managed for a later Apply. The everyday iteration teardown during development. Durables continue to bill while Parked.
_Avoid_: soft destroy, soft teardown, down, halt, suspend, Destroy (ambiguous — say Park or Teardown)

**Teardown**:
Permanently remove every resource the Stack currently manages, including Durables, leaving State empty. Stack configuration stays in the repository and can be Applied again. Explicit full wipe — not the default iteration path.
_Avoid_: Destroy, wipe, delete resources, terraform destroy (when you mean this full removal); Purge (Workload-only)

**Component**:
An installable unit of Prefect’s mandatory Host shape, owned as a directory under `prefect/` with its own idempotent Component Setup. Today’s Components are the Service Network and the Edge. Workloads are not Components.
_Avoid_: Package, unit, service, module (when you mean this installable Prefect piece)

**Component Setup**:
The idempotent, declarative Host-side application of one Component’s desired state. After a successful Component Setup, that Component is in the correct state. Reads that Component’s source tree from the Host Volume (and may source shared Host-local helpers from `/var/lib/prefect/components/lib/`); runs on the Host only; does not discover the Stack, SSH, or copy itself onto the Host. Used for first bring-up after Initial Host Provisioning and for later re-runs without Host recreation.
_Avoid_: Setup (bare), install, deploy, provision, Workload Setup (when you mean this Component action)

**Workload Setup**:
The idempotent, declarative Host-side application of one Workload’s Intent from its Manifest (Workload Intent, Public Hostnames, Route). Distinct from Component Setup; not part of ensuring Components. Distinct from Purge.
_Avoid_: Setup (bare), Component Setup, install, deploy, Purge (when you mean this Workload action)

**Edge**:
The mandatory public HTTP/HTTPS front door on a public Host. A Prefect Component (not optional). Sole publisher of Host ports 80/443; Workloads sit behind it. Terminates TLS for Public Hostnames and owns on-demand ACME (systemd user timer plus triggered runs when Public Hostnames change). On :80, only ACME challenges and HTTPS redirects — never Workload cleartext.
_Avoid_: Reverse proxy, ingress, gateway, nginx (when you mean this Prefect role — nginx is today’s implementation)

**Workload**:
An optional containerized service that runs on a Host. Not part of Prefect’s mandatory Host shape, not a Component, and never installed during Initial Host Provisioning; typically reached only via the Edge, not by publishing 80/443 itself.
_Avoid_: App, service, container, backend (when you mean this concept)

**Workload Manifest**:
A Workload-owned declaration that is the source of truth for that Workload’s Intent (**run**, **stop**, or **trash**), its Public Hostnames (one or more), and for producing its Route. First cut covers lifecycle and Edge reachability — not the Workload’s full runtime package beyond what Setup needs for those.
_Avoid_: Manifest (bare), spec, compose file, workload config (when you mean this declaration)

**Workload Intent**:
The Manifest’s post–Workload Setup expectation — what must be true after Setup succeeds; never Host status or a report of what is currently on the server. **run** (Quadlets up, Public Hostnames claimed, certificates renewed, Edge proxies to the Workload when a certificate exists), **stop** (no Quadlets; Public Hostnames still reserved; data and certificates kept; certificates not renewed; Edge answers 503 for those names while a certificate can terminate TLS, then goes dark after expiry), or **trash** (eligible for Purge; Public Hostnames released; associated data retained until Purge).
_Avoid_: Workload Desired State, desired state, running, stopped, trashed, active, disabled, remove, status, phase, current state (when you mean this Manifest field)

**Purge**:
The operation that permanently removes every Workload whose Intent is **trash** and its associated data (Routes, certificates, Host Volume Workload data, and related units). Does not affect Workloads whose Intent is **run** or **stop**.
_Avoid_: Teardown (Stack-level), Destroy, delete, cleanup, gc (when you mean this Workload operation)

**Public Hostname**:
An enumerated FQDN pointed at a public Host’s Reserved IP for which the Edge terminates TLS. Declared on a Workload Manifest (one or more per Workload); unique among Workloads on that Host that still claim it (Intent **run** or **stop**); not a DNS zone and not an open-ended wildcard. DNS (A/AAAA → Reserved IP) is out of band — not a Component.
_Avoid_: Domain, subdomain, vhost, server name, DNS name (when you mean this Prefect concept)

**Service Network**:
The private container network on a Host that the Edge and Workloads join so they can reach each other by name. Owned by Prefect as its own Component (not by the Edge). Distinct from the provider Firewall.
_Avoid_: Podman network, bridge, CNI (implementation); network (bare — ambiguous with Firewall / provider networking)

**Route**:
What the Edge loads for a Workload’s Public Hostnames. Projected from the stored Workload Manifest (Workload Intent, Public Hostnames, TLS wiring, optional **interior**) by Workload Setup and again by Edge ACME after successful issue/renew so HTTPS can go live without a second Setup: generated Edge shell plus either a generated proxy body or an optional Workload-provided interior (proxy body only — must not declare Public Hostnames). For Intent **run**, the HTTPS shell proxies to the Workload once a certificate exists; for Intent **stop**, the HTTPS shell returns 503 while a certificate lasts. The Edge’s own include shell and empty-routes stub remain Component-owned; Workload Routes must not be cleared by Component Setup.
_Avoid_: Vhost, upstream, location block, snippet, server block (implementation)

**Prefect User**:
The Host login account that runs Prefect’s rootless user Quadlets (linger enabled so user systemd stays up without an interactive session). Created by Initial Host Provisioning on public Hosts — account and linger only, not Quadlet units.
_Avoid_: edge user, podman user, service account (when you mean this Host account)
