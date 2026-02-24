# # OUTPUTS
# output "api_endpoint" {
#   value = local.k3s_api_load_balancer_ip
# }

# output "public_ingress_ip" {
#   value = hcloud_load_balancer.ingress.ipv4
# }

# output "control_plane_ids" {
#   value = concat([hcloud_server.control_plane_init.id], hcloud_server.control_plane_join[*].id)
# }

# output "worker_ids" {
#   value = hcloud_server.agent[*].id
# }

output "nat_public_ip" {
  value = hcloud_server.nat.ipv4_address
}
