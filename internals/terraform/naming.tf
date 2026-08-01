# Account-unique provider names for the current Environment (ADR-0019).
# Workspace `default` is the test Environment; its cloud name slug is `test`.
# Every provider `name` must come from this map — see lib/check-stack-names.sh.

locals {
  environment_slug = terraform.workspace == "default" ? "test" : terraform.workspace

  names = {
    propraetor_tag = "propraetor-${local.environment_slug}"
    role_tag       = "propraetor-${local.environment_slug}-public-web"
    host           = "propraetor-${local.environment_slug}-web"
    volume         = "propraetor-${local.environment_slug}-web-data"
    firewall       = "propraetor-${local.environment_slug}-public-web"
    project        = "propraetor-${local.environment_slug}"
  }
}
