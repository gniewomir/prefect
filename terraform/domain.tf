# Domain assignment projection for the Durable module.

locals {
  domains_path = "${path.module}/../config/environments/${local.environment_slug}/domains.json"
  domains_raw  = fileexists(local.domains_path) ? jsondecode(file(local.domains_path)) : {}
  domains = {
    for zone, cfg in local.domains_raw : zone => {
      names = [for name in cfg.names : name]
    }
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
