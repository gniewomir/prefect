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
