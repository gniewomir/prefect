# Renders Initial Host Provisioning user_data for the recreatables Host.
# Sole owner of the web.yaml embed recipe (jsonencode for executable script bytes).

output "user_data" {
  description = "cloud-init user_data document delivered to the Host."
  value = templatefile("${path.module}/web.yaml", {
    volume_name              = var.volume_name
    ssh_port                 = var.ssh_port
    host_root_ssh_public_key = var.host_root_ssh_public_key
    # jsonencode -> YAML double-quoted string: valid cloud-config without an
    # indent/literal-block leading newline (that broke the shebang: Exec format error).
    ensure_host_volume_mount_sh = jsonencode(file("${path.module}/ensure-host-volume-mount.sh"))
  })
}
