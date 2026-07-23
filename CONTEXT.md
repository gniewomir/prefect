# Prefect

Infrastructure-as-code for the Prefect platform office. This repository holds Terraform stacks that provision and manage the cloud resources other projects run on.

## Language

**Prefect**:
The standing office responsible for the platform domain (Hosts, networks, environments) so other projects can exist there — without deciding what those projects are. From Latin *praefectus*: an appointed authority placed over a defined sphere under delegated power, not ownership of the work’s purpose. Prefect-specific environment inputs use the `PREFECT_` prefix; provider-conventional Credential names and Terraform `TF_VAR_` inputs stay as those tools expect them.
_Avoid_: Infra, platform repo, DevOps project (when you mean this office)

**Stack**:
A Terraform root module that owns a cohesive slice of infrastructure for one provider or concern. Today the only stack is DigitalOcean (past Bootstrap: it manages Hosts and related network resources).
_Avoid_: Project, environment, workspace (those mean different things)

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

**Reserved IP**:
A stable public IPv4 address owned by the Stack and assigned to a Host. It survives Host rebuilds; the Host's own public IP does not.
_Avoid_: Floating IP, static IP, elastic IP (when you mean this address resource)

**Firewall**:
A provider-enforced network filter attached to Hosts. Inbound default deny (only SSH, HTTP, HTTPS, and ICMP allowed); outbound unrestricted. The Stack does not manage a host-level firewall.
_Avoid_: Security group, ufw, iptables, cloud firewall (product name when you mean this concept)
