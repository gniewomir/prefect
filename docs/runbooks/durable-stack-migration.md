# Durable Stack shape — operator notes

ADR-0016 / issue #24. Reserved IP is a Durable address plus a separate Host assignment; Host Volume, Domain, and the address refuse destroy unless Teardown unlocks them.

**Environment (ADR-0019):** `./apply.sh`, `./park.sh`, and `./teardown.sh` are safe by default — no `--env` selects the **test** Environment (Terraform workspace `default`). `--env test` and `--env default` mean the same Environment; any other slug (e.g. `--env prod`) must be passed explicitly. Scripts always select that workspace for the invocation (they do not trust a leftover current workspace).

## Park

`./park.sh [--env <slug>]` destroys every address in State **except** a preserve whitelist (Durables + Cloud Project + Reserved IP floatingip membership + the Durable unlock gate). New non-durables are Parked automatically without updating the script. Durables also carry `lifecycle.prevent_destroy` — that is the Durable source of truth if the whitelist drifts. Config is unchanged; the next `./apply.sh` recreates non-durables. Already Parked: exits 0 when State is only preserved addresses.

## Apply

`./apply.sh [--yes] [--env <slug>]` brings the Stack to desired managed presence. Interactive Terraform confirm by default; `--yes` for automation. Specialist Stack surgery stays raw `terraform` in the Stack dir (raw CLI lands on workspace `default` = test unless you `terraform workspace select` yourself).

## Durable destroy unlock

Terraform requires `lifecycle.prevent_destroy` to be a **literal** (it cannot read `var.allow_durable_destroy`). The Stack therefore uses both:

1. `-var=allow_durable_destroy=true` (default `false`)
2. An override file `terraform/durable_destroy_override.tf` that sets `prevent_destroy = false` on the Durables

A `terraform_data` precondition requires the variable and the override file to agree, so a bare `-var=allow_durable_destroy=true` without the override fails closed, and a leftover override with the default var also fails closed.

`./teardown.sh [--env <slug>]` owns this sequence: it copies `durable_destroy_override.tf.example` to `durable_destroy_override.tf`, runs destroy with `-var=allow_durable_destroy=true`, and removes the override on exit (success or failure). Do not leave `durable_destroy_override.tf` in the tree after Teardown.

Manual equivalent (prefer `./teardown.sh`):

```bash
cd terraform
cp durable_destroy_override.tf.example durable_destroy_override.tf
terraform destroy -var=allow_durable_destroy=true
rm -f durable_destroy_override.tf
```


## One-time State migration (Reserved IP split)

Older stacks bound the Host on the address resource:

```hcl
resource "digitalocean_reserved_ip" "web" {
  region     = digitalocean_droplet.web.region
  droplet_id = digitalocean_droplet.web.id
}
```

Current shape: address has `region` only; `digitalocean_reserved_ip_assignment.web` holds the Host binding.

### If Apply alone is enough

From the Stack directory, with Credentials set:

```bash
terraform plan
```

Expect roughly:

- **update** `digitalocean_reserved_ip.web` (drop `droplet_id`; region stays `fra1`)
- **create** `digitalocean_reserved_ip_assignment.web`
- **update** Durables with `prevent_destroy` (State metadata only)

If the plan **replaces** `digitalocean_reserved_ip.web` (new address), **do not apply** — that would change the Reserved IP value. Use the import path below.

If the plan only updates/creates as above:

```bash
terraform apply
```

A brief unassign/reassign may occur; DNS at the same address should keep working.

### If the plan wants to replace the Reserved IP

Keep the existing address; import the assignment and fix State:

```bash
# IP and droplet id from current State / provider
IP="$(terraform output -raw reserved_ip)"
DROPLET_ID="$(terraform state show -no-color digitalocean_droplet.web | awk '/^id / {print $3; exit}')"

# After updating .tf to the split shape, remove the old binding from the address
# in State if plan still forces replacement — prefer provider UI/API only if TF
# cannot update in place; then:
terraform import digitalocean_reserved_ip_assignment.web "${IP},${DROPLET_ID}"
terraform plan   # must not replace digitalocean_reserved_ip.web
terraform apply
```

Empty State (fresh Apply) needs no migration: Apply creates address + assignment together.
