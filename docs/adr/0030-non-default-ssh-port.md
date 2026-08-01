# Non-default SSH port (noise mitigation)

Public Host Firewall SSH stays open from `0.0.0.0/0`. Opportunistic scanners on `:22` exhaust `sshd` `MaxStartups` and flake Acceptance SSH. We move SSH off the default port as **noise mitigation only** — not a security boundary. VPN-only access, IP allowlists, and sshd rate-limits (`PerSourceMaxStartups`, etc.) remain deferred alternatives.

**Cutover (DigitalOcean documented path):** IHP writes `Port` under `sshd_config.d`, then cloud-init `power_state: reboot` once per instance so the Host Image picks up the listen port ([DO: change Droplet SSH port](https://docs.digitalocean.com/support/how-do-i-change-my-droplets-ssh-port/)). Do not `systemctl restart ssh.socket` mid-boot as the sole cutover — that locked Hosts on Ubuntu 26.04. Firewall allows only the Propraetor port; classic `:22` is DROPped. First boot is unreachable on `:22` until the IHP reboot finishes — operator SSH uses the twin port after IHP Done.

**IHP YAML:** Embedded Host Volume script bytes go through `indent(format("\n%s", file(...)))`. Plain `indent(file(...))` leaves the shebang at column 0, which invalidates the whole cloud-config — Port, `power_state`, and volume setup never apply (symptom: `:9417` refused, `:22` still listening, no `99-ssh-port.conf`).

**Constants:** one Terraform value drives Firewall inbound and the IHP `templatefile`; one shell constant drives all clients. They must stay twins — no cross-language single source. The digit string is implementation, not glossary language (Firewall/Host keep abstract “SSH”; Edge’s `80`/`443` remain the only product-surface ports).

**Acceptance:** probe SSH (via the shell constant) plus `80`/`443` as allowed; assert classic `:22` is Firewall-filtered (DROP, not refused), same shape as other denied TCP.
