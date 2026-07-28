# Non-default SSH port (noise mitigation)

Public Host Firewall SSH stays open from `0.0.0.0/0`. Opportunistic scanners on `:22` exhaust `sshd` `MaxStartups` and flake Acceptance SSH. We move SSH off the default port as **noise mitigation only** — not a security boundary. VPN-only access, IP allowlists, and sshd rate-limits (`PerSourceMaxStartups`, etc.) remain deferred alternatives.

**Cutover:** Firewall allow, sshd listen (`Port` in Initial Host Provisioning), and every operator/Acceptance SSH/SCP client change in one Apply. Mismatch locks the operator out. sshd Port is IHP (Host recreate), not a post-carrier mutation path.

**Constants:** one Terraform value drives Firewall inbound and the IHP `templatefile`; one shell constant drives all clients. They must stay twins — no cross-language single source. The digit string is implementation, not glossary language (Firewall/Host keep abstract “SSH”; Edge’s `80`/`443` remain the only product-surface ports).

**Acceptance:** probe SSH (via the shell constant) plus `80`/`443` as allowed; assert classic `:22` is Firewall-filtered (DROP, not refused), same shape as other denied TCP.
