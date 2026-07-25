# Account-unique provider names for the current Environment (ADR-0019).
# Workspace `default` is the test Environment; its cloud name slug is `test`.
# Every provider `name` must come from this map — see lib/check-stack-names.sh.

locals {
  environment_slug = terraform.workspace == "default" ? "test" : terraform.workspace

  names = {
    prefect_tag = "prefect-${local.environment_slug}"
    role_tag    = "prefect-${local.environment_slug}-public-web"
    ssh_key     = "prefect-${local.environment_slug}-web"
    host        = "prefect-${local.environment_slug}-web"
    volume      = "prefect-${local.environment_slug}-web-data"
    firewall    = "prefect-${local.environment_slug}-public-web"
    project     = "prefect-${local.environment_slug}"
  }
}
