# NETWORK
resource "hcloud_network" "main" {
  name     = "${local.prefix}-vnet"
  ip_range = var.vpc_cidr
}

resource "hcloud_network_subnet" "k3s_nodes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = local.net_zone
  ip_range     = local.net_nodes_cidr
}

# NAT & BASTION GATEWAY
resource "hcloud_server" "nat" {
  name        = "${local.prefix}-nat"
  server_type = var.nat_type
  image       = data.hcloud_image.nat.id
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = var.network_gateway
  }

  labels = {
    cluster = local.prefix
    role    = "nat-gateway"
  }

  depends_on = [hcloud_network_subnet.k3s_nodes]

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Enable IP Forwarding (Critical for NAT)
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    echo "--- Applying VPC NAT Routing ---"
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -o eth0 -j MASQUERADE
    apt-get update && apt-get install -y iptables-persistent
    netfilter-persistent save

    echo "--- Starting Tailscale Join Loop ---"
    NEXT_WAIT_TIME=0
    until tailscale up \
      --authkey=${var.tailscale_auth_nat_key} \
      --ssh \
      --hostname=${local.prefix}-nat \
      --advertise-tags="{tag:nat}" \
      --advertise-routes=${var.vpc_cidr} \
      --reset >> /var/log/tailscale-join.log 2>&1 || [ $NEXT_WAIT_TIME -eq 12 ];
    do
      echo "Join failed. Retrying in 5 seconds..." >> /var/log/tailscale-join.log
      sleep 5
      NEXT_WAIT_TIME=$((NEXT_WAIT_TIME+1))
    done
  EOF
}

# INTERNET EXIT ROUTE
resource "hcloud_network_route" "default_gateway" {
  network_id  = hcloud_network.main.id
  destination = "0.0.0.0/0"
  gateway     = var.network_gateway
}

# LOAD BALANCERS
resource "hcloud_load_balancer" "k3s_api" {
  name               = "${local.prefix}-api-lb"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "api_lb_net" {
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  network_id       = hcloud_network.main.id
}

resource "hcloud_load_balancer_service" "api_service" {
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "hcloud_load_balancer" "k3s_ingress" {
  name               = "${local.prefix}-ingress-lb"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "ingress_lb_net" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  network_id       = hcloud_network.main.id
}

resource "hcloud_load_balancer_service" "ingress_http" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80
  proxyprotocol    = true

  health_check {
    protocol = "http"
    port     = 10254
    interval = 10
    timeout  = 5
    retries  = 3
    http { path = "/healthz" }
  }
}

resource "hcloud_load_balancer_service" "ingress_https" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443
  proxyprotocol    = true

  health_check {
    protocol = "http"
    port     = 10254
    interval = 10
    timeout  = 5
    retries  = 3
    http { path = "/healthz" }
  }
}
