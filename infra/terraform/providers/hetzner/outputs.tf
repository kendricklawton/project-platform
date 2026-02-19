# OUTPUTS
output "ip_api_endpoint" {
  value = local.ip_api_lb
}

output "ip_ingress_endpoint" {
  value = local.ip_ingress_lb
}

output "id_control_plane_nodes" {
  value = concat([hcloud_server.cp_init.id], hcloud_server.cp_join[*].id)
}

output "id_worker_nodes" {
  value = hcloud_server.worker[*].id
}

output "ip_control_plane_nodes" {
  value = concat([hcloud_server.cp_init.ipv4_address], hcloud_server.cp_join[*].ipv4_address)
}

output "ip_worker_nodes_list" {
  value = hcloud_server.worker[*].ipv4_address
}
