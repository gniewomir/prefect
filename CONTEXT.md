# Infra

Infrastructure-as-code for cloud resources. This repository holds Terraform stacks that provision and manage platform infrastructure.

## Language

**Stack**:
A Terraform root module that owns a cohesive slice of infrastructure for one provider or concern. Today the only stack is DigitalOcean, starting as bootstrap (provider, auth, and state) with no managed resources yet.
_Avoid_: Project, environment, workspace (those mean different things)

**Bootstrap**:
The initial content of a Stack: provider configuration, version pins, authentication wiring, and state backend — deliberately without managed cloud resources.
_Avoid_: Scaffold, skeleton, hello-world

**State**:
The Terraform record of what a Stack currently manages. For Bootstrap, State is local to the operator's machine.
_Avoid_: Backend, tfstate (implementation jargon for the concept itself)

**Credential**:
A secret used to authenticate to a cloud provider. Supplied via the environment (never committed); for DigitalOcean that is the API token in `DIGITALOCEAN_TOKEN`.
_Avoid_: Key, secret, password (when you mean the provider API token)
