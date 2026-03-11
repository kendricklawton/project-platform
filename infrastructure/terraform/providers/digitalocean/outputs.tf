# OUTPUTS
output "nat_public_ip" {
  value = digitalocean_droplet.nat.ipv4_address
}

output "api_endpoint" {
  value = digitalocean_loadbalancer.api.ip
}

output "control_plane_init_hostname" {
  description = "Tailscale hostname of the primary control plane node for SSH access"
  value       = digitalocean_droplet.control_plane_init.name
}

output "public_ingress_ip" {
  value = digitalocean_loadbalancer.ingress.ip
}

output "control_plane_ids" {
  value = concat(
    [digitalocean_droplet.control_plane_init.id],
    [for d in digitalocean_droplet.control_plane_join : d.id]
  )
}

output "worker_ids" {
  value = [for d in digitalocean_droplet.worker : d.id]
}
