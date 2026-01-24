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
  }
}

variable "hcloud_token" { sensitive = true }
variable "tailscale_auth_nat_key" { sensitive = true }
variable "tailscale_auth_server_key" { sensitive = true }
variable "tailscale_auth_agent_key" { sensitive = true }
variable "ssh_key_name" { type = string }
variable "gcp_project_id" { type = string }
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
    "ash"  = "us-east"
    "hil"  = "us-west"
    "nbg1" = "eu-central"
  }

  network_zone = local.location_zone_map[var.hcloud_location]

  nat_user_data = templatefile("${path.module}/cloud-init-nat.yaml", {
    tailscale_auth_nat_key = var.tailscale_auth_nat_key
    hostname               = "${local.prefix}-nat-${var.hcloud_location}"
  })

  config = {
    dev  = { master_type = "cpx21", worker_type = "cpx21", worker_count = 1 }
    prod = { master_type = "cpx41", worker_type = "cpx41", worker_count = 3 }
  }
  env = local.config[var.cloud_env]
}

data "hcloud_image" "k3s_ash" {
  with_selector = "role=k3s-base,region=ash"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

resource "hcloud_network" "east" {
  name     = "${local.prefix}-vnet-east"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k3s_east" {
  network_id   = hcloud_network.east.id
  type         = "cloud"
  network_zone = "us-east"
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_server" "nat_east" {
  name        = "${local.prefix}-nat-ash"
  image       = "ubuntu-24.04"
  server_type = "cpx11"
  location    = "ash"
  ssh_keys    = [data.hcloud_ssh_key.admin.id]
  labels      = { role = "nat" }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.east.id
    ip         = "10.0.1.2"
  }

  user_data  = local.nat_user_data
  depends_on = [hcloud_network_subnet.k3s_east]
}

resource "time_sleep" "wait_for_nat_config" {
  depends_on      = [hcloud_server.nat_east]
  create_duration = "120s"
}

resource "hcloud_network_route" "route_east" {
  network_id  = hcloud_network.east.id
  destination = "0.0.0.0/0"
  gateway     = "10.0.1.2"
  depends_on  = [hcloud_server.nat_east]
}

resource "hcloud_load_balancer" "main" {
  name               = "${local.prefix}-lb-api"
  load_balancer_type = "lb11"
  location           = "ash"
}

resource "hcloud_load_balancer_network" "serve_net" {
  load_balancer_id = hcloud_load_balancer.main.id
  network_id       = hcloud_network.east.id
  ip               = "10.0.1.254"
  depends_on       = [hcloud_network_subnet.k3s_east]
}

resource "hcloud_load_balancer_service" "k3s_api" {
  load_balancer_id = hcloud_load_balancer.main.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443
}

resource "hcloud_load_balancer_target" "k3s_api_targets" {
  count            = 1
  type             = "server"
  load_balancer_id = hcloud_load_balancer.main.id
  server_id        = module.control_plane[count.index].id
  use_private_ip   = true
}

resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

module "control_plane" {
  source                    = "./modules/k3s_node"
  count                     = 1
  name                      = "${local.prefix}-server-${count.index}"
  private_ip                = "10.0.1.3"
  k3s_init                  = true
  location                  = "ash"
  image                     = data.hcloud_image.k3s_ash.id
  server_type               = local.env.master_type
  ssh_key_ids               = [data.hcloud_ssh_key.admin.id]
  network_id                = hcloud_network.east.id
  project_name              = local.prefix
  node_role                 = "server"
  k3s_token                 = random_password.k3s_token.result
  lb_ip                     = "10.0.1.254"
  tailscale_auth_server_key = var.tailscale_auth_server_key
  hcloud_token              = var.hcloud_token
  hcloud_network_name       = hcloud_network.east.name
  s3_access_key             = var.etcd_s3_access_key
  s3_secret_key             = var.etcd_s3_secret_key
  s3_bucket                 = var.etcd_s3_bucket

  depends_on = [
    hcloud_network_route.route_east,
    time_sleep.wait_for_nat_config
  ]
}

module "worker_agents" {
  source                   = "./modules/k3s_node"
  count                    = local.env.worker_count
  name                     = "${local.prefix}-agent-${count.index}"
  private_ip               = "10.0.1.${count.index + 4}" # Starts at 10.0.1.4
  location                 = "ash"
  image                    = data.hcloud_image.k3s_ash.id
  server_type              = local.env.worker_type
  ssh_key_ids              = [data.hcloud_ssh_key.admin.id]
  network_id               = hcloud_network.east.id
  project_name             = local.prefix
  node_role                = "agent"
  k3s_token                = random_password.k3s_token.result
  lb_ip                    = "10.0.1.254"
  tailscale_auth_agent_key = var.tailscale_auth_agent_key
  hcloud_token             = var.hcloud_token
  hcloud_network_name      = hcloud_network.east.name

  depends_on = [
    hcloud_network_route.route_east,
    time_sleep.wait_for_nat_config
  ]
}

resource "hcloud_firewall" "cluster_fw" {
  name = "${local.prefix}-fw"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["10.0.0.0/16"]
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = ["10.0.0.0/16"]
  }
  apply_to { label_selector = "cluster=${local.prefix}" }
}

output "lb_public_ip" {
  value = hcloud_load_balancer.main.ipv4
}
