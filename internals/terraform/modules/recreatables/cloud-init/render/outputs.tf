# Renders Initial Host Provisioning user_data for the recreatables Host.
# Sole owner of the web.yaml embed recipe (indent + leading newline for YAML).

output "user_data" {
  description = "cloud-init user_data document delivered to the Host."
  value = templatefile("${path.module}/web.yaml", {
    volume_name              = var.volume_name
    ssh_port                 = var.ssh_port
    host_root_ssh_public_key = var.host_root_ssh_public_key
    # indent() does not prefix the first line; a leading newline makes every
    # script line indented so the YAML literal block under content: | stays valid.
    ensure_host_volume_mount_sh = indent(6, format("\n%s", file("${path.module}/ensure-host-volume-mount.sh")))
  })
}
