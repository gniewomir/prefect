# Domain assignment projection for the Durable module (ADR-0021).
# Prefer domains.override.json when present; otherwise domains.json.
# Config stays at repository root; Stack root is internals/terraform/ (ADR-0032).

locals {
  domains_dir            = "${path.root}/../../config/environments/${local.environment_slug}"
  domains_override_path  = "${local.domains_dir}/domains.override.json"
  domains_committed_path = "${local.domains_dir}/domains.json"
  domains_path = (
    fileexists(local.domains_override_path)
    ? local.domains_override_path
    : local.domains_committed_path
  )
  domains_raw = fileexists(local.domains_path) ? jsondecode(file(local.domains_path)) : {}
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
