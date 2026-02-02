terraform {
  required_version = ">= 1.5.0"
  backend "gcs" {}
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }
}

variable "hcloud_token" { sensitive = true }
variable "api_load_balancer_ip" {
  description = "Static internal IP for the API Server (Control Plane)"
  default     = "10.0.1.254"
}
variable "tailscale_auth_nat_key" { sensitive = true }
variable "tailscale_auth_k3s_server_key" { sensitive = true }
variable "tailscale_auth_k3s_agent_key" { sensitive = true }
variable "ssh_key_name" { type = string }
variable "gcp_project_id" { type = string }
variable "letsencrypt_email" { type = string }
variable "cloud_env" { type = string }
variable "project_name" { type = string }
variable "image_version" { type = string }
variable "hcloud_location" {
  type    = string
  default = "ash"
}
variable "etcd_s3_bucket" { type = string }
variable "etcd_s3_access_key" { sensitive = true }
variable "etcd_s3_secret_key" { sensitive = true }

provider "hcloud" {
  token = var.hcloud_token
}

locals {
  prefix = "${var.cloud_env}-${var.project_name}"

  location_zone_map = {
    "ash" = "us-east"
    "hil" = "us-west"
  }
  network_zone = local.location_zone_map[var.hcloud_location]

  config = {
    dev  = { nat_type = "cpx11", master_type = "cpx21", master_count = 1, worker_type = "cpx21", worker_count = 1 }
    prod = { nat_type = "cpx11", master_type = "cpx21", master_count = 3, worker_type = "cpx41", worker_count = 3 }
  }
  env = local.config[var.cloud_env]

  nat_user_data = templatefile("${path.module}/cloud-init-nat.yaml", {
    tailscale_auth_nat_key = var.tailscale_auth_nat_key
    hostname               = "${local.prefix}-nat-${var.hcloud_location}"
    tailscale_tag          = "nat"
  })
}

data "hcloud_image" "k3s_base" {
  with_selector = "role=k3s-base,region=${var.hcloud_location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

resource "hcloud_network" "main" {
  name     = "${local.prefix}-vnet-${var.hcloud_location}"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k3s_nodes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_server" "nat" {
  name        = "${local.prefix}-nat-${var.hcloud_location}"
  image       = "ubuntu-24.04"
  server_type = local.env.nat_type
  location    = var.hcloud_location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]
  labels      = { role = "nat" }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = "10.0.1.2"
  }

  user_data  = local.nat_user_data
  depends_on = [hcloud_network_subnet.k3s_nodes]
}

resource "time_sleep" "wait_for_nat_config" {
  depends_on      = [hcloud_server.nat]
  create_duration = "120s"
}

resource "hcloud_network_route" "default_route" {
  network_id  = hcloud_network.main.id
  destination = "0.0.0.0/0"
  gateway     = "10.0.1.2"
  depends_on  = [hcloud_server.nat]
}

resource "hcloud_load_balancer" "api" {
  name               = "${local.prefix}-lb-api-${var.hcloud_location}"
  load_balancer_type = "lb11"
  location           = var.hcloud_location
}

resource "hcloud_load_balancer_network" "api_net" {
  load_balancer_id = hcloud_load_balancer.api.id
  network_id       = hcloud_network.main.id
  ip               = var.api_load_balancer_ip
  depends_on       = [hcloud_network_subnet.k3s_nodes]
}

resource "hcloud_load_balancer_service" "k3s_api" {
  load_balancer_id = hcloud_load_balancer.api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "http"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
    http {
      path = "/healthz"
      tls  = true
    }
  }
}

resource "hcloud_load_balancer" "ingress" {
  name               = "${local.prefix}-lb-ingress-${var.hcloud_location}"
  load_balancer_type = "lb11"
  location           = var.hcloud_location
}

resource "hcloud_load_balancer_network" "ingress_net" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  network_id       = hcloud_network.main.id
  depends_on       = [hcloud_network_subnet.k3s_nodes]
}

resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80
  proxyprotocol    = true

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443
  proxyprotocol    = true

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

module "control_plane_init" {
  source                    = "./modules/k3s_node"
  cloud_env                 = var.cloud_env
  letsencrypt_email         = var.letsencrypt_email
  hostname                  = format("${local.prefix}-k3s-server-%02d", 1)
  location                  = var.hcloud_location
  image                     = data.hcloud_image.k3s_base.id
  server_type               = local.env.master_type
  ssh_key_ids               = [data.hcloud_ssh_key.admin.id]
  network_id                = hcloud_network.main.id
  project_name              = local.prefix
  node_role                 = "server"
  k3s_token                 = random_password.k3s_token.result
  load_balancer_ip          = var.api_load_balancer_ip
  k3s_init                  = true
  tailscale_auth_server_key = var.tailscale_auth_k3s_server_key
  hcloud_token              = var.hcloud_token
  hcloud_network_name       = hcloud_network.main.name
  s3_access_key             = var.etcd_s3_access_key
  s3_secret_key             = var.etcd_s3_secret_key
  s3_bucket                 = var.etcd_s3_bucket

  depends_on = [hcloud_network_route.default_route, time_sleep.wait_for_nat_config]
}

resource "hcloud_load_balancer_target" "api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = module.control_plane_init.id
  use_private_ip   = true
}

resource "time_sleep" "wait_for_init_node" {
  depends_on      = [module.control_plane_init, hcloud_load_balancer_target.api_target_init]
  create_duration = "120s"
}

module "control_plane_join" {
  source                    = "./modules/k3s_node"
  count                     = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  cloud_env                 = var.cloud_env
  letsencrypt_email         = var.letsencrypt_email
  hostname                  = format("${local.prefix}-k3s-server-%02d", count.index + 2)
  location                  = var.hcloud_location
  image                     = data.hcloud_image.k3s_base.id
  server_type               = local.env.master_type
  ssh_key_ids               = [data.hcloud_ssh_key.admin.id]
  network_id                = hcloud_network.main.id
  project_name              = local.prefix
  node_role                 = "server"
  k3s_token                 = random_password.k3s_token.result
  load_balancer_ip          = var.api_load_balancer_ip
  k3s_init                  = false
  tailscale_auth_server_key = var.tailscale_auth_k3s_server_key
  hcloud_token              = var.hcloud_token
  hcloud_network_name       = hcloud_network.main.name
  s3_access_key             = var.etcd_s3_access_key
  s3_secret_key             = var.etcd_s3_secret_key
  s3_bucket                 = var.etcd_s3_bucket
  depends_on                = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "api_targets_join" {
  count            = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = module.control_plane_join[count.index].id
  use_private_ip   = true
}

module "worker_agents" {
  source                   = "./modules/k3s_node"
  count                    = local.env.worker_count
  cloud_env                = var.cloud_env
  hostname                 = format("${local.prefix}-k3s-agent-%02d", count.index + 1)
  location                 = var.hcloud_location
  image                    = data.hcloud_image.k3s_base.id
  server_type              = local.env.worker_type
  ssh_key_ids              = [data.hcloud_ssh_key.admin.id]
  network_id               = hcloud_network.main.id
  project_name             = local.prefix
  node_role                = "agent"
  k3s_token                = random_password.k3s_token.result
  load_balancer_ip         = var.api_load_balancer_ip
  tailscale_auth_agent_key = var.tailscale_auth_k3s_agent_key
  hcloud_token             = var.hcloud_token
  hcloud_network_name      = hcloud_network.main.name
  depends_on               = [time_sleep.wait_for_init_node, module.control_plane_join]
}

resource "hcloud_load_balancer_target" "ingress_targets" {
  count            = local.env.worker_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress.id
  server_id        = module.worker_agents[count.index].id
  use_private_ip   = true
}

resource "hcloud_firewall" "cluster_fw" {
  name = "${local.prefix}-fw-${var.hcloud_location}"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["10.0.0.0/16"]
  }

  # Kubelet API (Internal Only - needed for kubectl logs/exec)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = ["10.0.0.0/16"]
  }

  # VXLAN / Flannel (Internal Only)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = ["10.0.0.0/16"]
  }

  # Cilium Health Checks (Internal Only)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "4240"
    source_ips = ["10.0.0.0/16"]
  }

  # Cilium VXLAN (Internal Only)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8473"
    source_ips = ["10.0.0.0/16"]
  }

  # etcd (Internal Only - for HA control plane)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379-2380"
    source_ips = ["10.0.0.0/16"]
  }

  # HTTP/HTTPS (Internal Only - LB forwards to these)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["10.0.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["10.0.0.0/16"]
  }

  # Tailscale UDP (Allow from anywhere for direct connections)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # WireGuard (Tailscale fallback)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  apply_to { label_selector = "cluster=${local.prefix}" }
}

output "api_endpoint" {
  description = "Cluster Management Endpoint (Private)"
  value       = var.api_load_balancer_ip
}

output "public_ingress_ip" {
  description = "POINT CLOUDFLARE HERE for your Users"
  value       = hcloud_load_balancer.ingress.ipv4
}

output "control_plane_ids" {
  description = "IDs of all control plane nodes"
  value       = concat([module.control_plane_init.id], module.control_plane_join[*].id)
}

output "worker_ids" {
  description = "IDs of all worker nodes"
  value       = module.worker_agents[*].id
}
