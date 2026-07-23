# Prefect

Infrastructure-as-code for the Prefect platform office. This repository holds Terraform stacks that provision and manage the cloud resources other projects run on.

## Language

**Prefect**:
The standing office responsible for the platform domain (Hosts, networks, environments) so other projects can exist there — without deciding what those projects are. From Latin *praefectus*: an appointed authority placed over a defined sphere under delegated power, not ownership of the work’s purpose.
_Avoid_: Infra, platform repo, DevOps project (when you mean this office)

**Stack**:
A Terraform root module that owns a cohesive slice of infrastructure for one provider or concern. Today the only stack is DigitalOcean (past Bootstrap: it manages Hosts and related network resources).
_Avoid_: Project, environment, workspace (those mean different things — for the provider folder, see Cloud Project)

**Cloud Project**:
A provider-side folder that groups billable resources for UI and billing. Distinct from Prefect (the office) and from Stack (Terraform). The Stack creates the DigitalOcean Cloud Project named `Prefect` (purpose: shared projects infrastructure; environment: Production; not the account default) and assigns every assignable resource to it (today: the Host; a Reserved IP assigned to that Host follows automatically). Resources that cannot be assigned (Firewall, tags, SSH keys) stay Stack-managed only.
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
One-shot Host setup applied when the Host is created (delivered via the provider’s user-data / cloud-init). Not ongoing Host management and not Stack Bootstrap.
_Avoid_: User Data, cloud-init, userdata (when you mean this concept); provisioning (bare — ambiguous with Stack apply)

**Reserved IP**:
A stable public IPv4 address owned by the Stack and assigned to a Host. It survives Host rebuilds; the Host's own public IP does not.
_Avoid_: Floating IP, static IP, elastic IP (when you mean this address resource)

**Firewall**:
A provider-enforced network filter attached to Hosts. Inbound default deny (only SSH, HTTP, HTTPS, and ICMP allowed); outbound unrestricted. The Stack does not manage a host-level firewall. Attachment is by Role Tag, not by Host ID alone.
_Avoid_: Security group, ufw, iptables, cloud firewall (product name when you mean this concept)

**Office Tag**:
A provider tag that marks taggable resources as belonging to Prefect (name: `prefect`). Applied to every Prefect Host. Not all Stack resources are taggable (Firewall, Reserved IP, and SSH keys are not).
_Avoid_: Shared tag, prefect tag (when you mean this concept)

**Role Tag**:
A provider tag that selects Hosts for a policy such as a Firewall (public web: `prefect-public-web`). Orthogonal to the Office Tag; a Host may carry both.
_Avoid_: Firewall tag (ambiguous — the Firewall targets the Role Tag; it is not itself tagged)

**Acceptance Test**:
An executable check of Applied Stack external behavior (does the live Stack match the intended contract?). Requires an applied Stack and asserts observable outcomes only — not Terraform internals or provider API shape.
_Avoid_: Verify script, observability check, smoke test, integration test (when you mean this concept)

**Destroy**:
Permanently remove every resource the Stack currently manages, leaving State empty. Stack configuration stays in the repository and can be applied again. Used during development to iterate on the Stack quickly.
_Avoid_: Delete resources, teardown, terraform destroy (when you mean this full removal)

**Edge**:
The mandatory public HTTP/HTTPS front door on a public Host. Part of Prefect (not optional). Sole publisher of Host ports 80/443; Workloads sit behind it.
_Avoid_: Reverse proxy, ingress, gateway, nginx (when you mean this Prefect role — nginx is today’s implementation)

**Workload**:
An optional containerized service that runs on a Host. Not part of Prefect’s mandatory Host shape; typically reached only via the Edge, not by publishing 80/443 itself.
_Avoid_: App, service, container, backend (when you mean this concept)

**Service Network**:
The private container network on a Host that the Edge and Workloads join so they can reach each other by name. Owned by Prefect as its own piece (not by the Edge package). Distinct from the provider Firewall.
_Avoid_: Podman network, bridge, CNI (implementation); network (bare — ambiguous with Firewall / provider networking)

**Route**:
A Workload-contributed config fragment the Edge loads so that Workload is reachable through the Edge. The Edge ships the shell (includes drop-ins); each Workload owns its Route.
_Avoid_: Vhost, upstream, location block, snippet, server block (implementation)

**Prefect User**:
The Host login account that runs Prefect’s rootless user Quadlets (linger enabled so user systemd stays up without an interactive session). Created by Initial Host Provisioning on public Hosts — account and linger only, not Quadlet units.
_Avoid_: edge user, podman user, service account (when you mean this Host account)
