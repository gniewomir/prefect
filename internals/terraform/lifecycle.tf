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
    prefect_tag = local.names.prefect_tag
    role_tag    = local.names.role_tag
    ssh_key     = local.names.ssh_key
    host        = local.names.host
    firewall    = local.names.firewall
  }
  region              = "fra1"
  public_key          = var.DIGITALOCEAN_PUBLIC_KEY
  project_id          = module.durables.project_id
  reserved_ip_address = module.durables.reserved_ip_address
  volume_id           = module.durables.volume_id
  volume_name         = module.durables.volume_name

  # The whole Durable graph, including memberships, converges before any
  # Recreatable operation begins.
  depends_on = [module.durables]
}
