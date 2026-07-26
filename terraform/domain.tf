# Domain Durables (ADR-0020): provider zone + Stack-authored A records → Reserved IP.
# Park keeps them; Teardown unlocks via allow_durable_destroy + override (ADR-0016).
# Prefer no create-time ip_address — apex A is an explicit digitalocean_record.

variable "domains" {
  type = map(object({
    names = list(string)
  }))
  default     = {}
  description = <<-EOT
    Domain Durables keyed by apex FQDN (e.g. example.com). Each entry's names
    are Stack-authored A record labels (@ for apex, www, …) pointing at the
    Environment Reserved IP. Empty map = zero Domains. Set via TF_VAR_domains
    (JSON) or a .tfvars file. Registrar NS → provider stays out of band.
  EOT

  validation {
    condition = alltrue([
      for _zone, cfg in var.domains : length(cfg.names) > 0
    ])
    error_message = "Each Domain must declare at least one name (A → Reserved IP)."
  }
}

locals {
  domain_a_records = {
    for pair in flatten([
      for zone, cfg in var.domains : [
        for name in cfg.names : {
          key  = "${zone}:${name}"
          zone = zone
          name = name
        }
      ]
    ]) : pair.key => pair
  }
}

resource "digitalocean_domain" "this" {
  for_each = var.domains

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

  lifecycle {
    prevent_destroy = true
  }
}
