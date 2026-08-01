module "durables" {
  source = "./modules/durables"

  names = {
    project = local.names.project
    volume  = local.names.volume
  }
  region        = "fra1"
  domains       = local.domains
  allow_destroy = var.allow_durable_destroy
}

module "recreatables" {
  count  = var.recreatables_present ? 1 : 0
  source = "./modules/recreatables"

  names = {
    propraetor_tag = local.names.propraetor_tag
    role_tag       = local.names.role_tag
    host           = local.names.host
    firewall       = local.names.firewall
  }
  region                   = "fra1"
  host_root_ssh_public_key = var.host_root_ssh_public_key
  host_image               = var.host_image
  project_id               = module.durables.project_id
  reserved_ip_address      = module.durables.reserved_ip_address
  volume_id                = module.durables.volume_id
  volume_name              = module.durables.volume_name

  # The whole Durable graph, including memberships, converges before any
  # Recreatable operation begins.
  depends_on = [module.durables]
}
