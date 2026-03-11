# --- FIREWALL RULES ---
# Applied to all droplets in this cluster via tag selector.
resource "digitalocean_firewall" "cluster_fw" {
  name = "${local.prefix}-fw"
  tags = [local.cp_tag, local.worker_tag]

  # INBOUND: HTTP/HTTPS (public)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # INBOUND: Tailscale direct (UDP 41641)
  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # INBOUND: Wireguard fallback (UDP 51820)
  inbound_rule {
    protocol         = "udp"
    port_range       = "51820"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # INBOUND: All traffic within the VPC
  inbound_rule {
    protocol         = "tcp"
    port_range       = "all"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "all"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # OUTBOUND: All traffic allowed
  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
