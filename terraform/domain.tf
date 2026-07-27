# Domain Durables (ADR-0020): provider zone + Stack-authored A records → Reserved IP.
# Assignment: committed config/environments/<cloud-slug>/domains.json (ADR-0021).
# Park keeps them; Teardown unlocks via allow_durable_destroy + override (ADR-0016).
# Prefer no create-time ip_address — apex A is an explicit digitalocean_record.

locals {
  domains_path = "${path.module}/../config/environments/${local.environment_slug}/domains.json"
  domains_raw  = fileexists(local.domains_path) ? jsondecode(file(local.domains_path)) : {}
  domains = {
    for zone, cfg in local.domains_raw : zone => {
      names = [for name in cfg.names : name]
    }
  }
  domain_a_records = {
    for pair in flatten([
      for zone, cfg in local.domains : [
        for name in cfg.names : {
          key  = "${zone}:${name}"
          zone = zone
          name = name
        }
      ]
    ]) : pair.key => pair
  }
}

check "domains_names_nonempty" {
  assert {
    condition = alltrue([
      for _zone, cfg in local.domains : length(cfg.names) > 0
    ])
    error_message = "Each Domain must declare at least one name (A → Reserved IP)."
  }
}

resource "digitalocean_domain" "this" {
  for_each = local.domains

  name = each.key

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "a" {
  for_each = local.domain_a_records

  domain = digitalocean_domain.this[each.value.zone].id
  type   = "A"
  name   = each.value.name
  value  = digitalocean_reserved_ip.web.ip_address
  # Explicit: provider default is 1800; omitting it makes import/read show TTL 0 and warn on every converge.
  ttl = 1800

  lifecycle {
    prevent_destroy = true
  }
}
