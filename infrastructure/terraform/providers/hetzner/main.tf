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

# VARIABLES
variable "project_name" { type = string }
variable "cloud_env" { type = string }
variable "token" { sensitive = true }
variable "ssh_key_name" { type = string }
variable "location" { type = string }

# Server Types
variable "k3s_server_type" { type = string }
variable "k3s_agent_type" { type = string }
variable "nat_gateway_type" { type = string }
variable "load_balancer_type" { type = string }
variable "git_repo_url" { type = string }

# Tailscale
variable "tailscale_auth_nat_key" { sensitive = true }
variable "tailscale_auth_k3s_server_key" { sensitive = true }
variable "tailscale_auth_k3s_agent_key" { sensitive = true }

# S3 Backup Bucket
variable "etcd_s3_access_key" { sensitive = true }
variable "etcd_s3_secret_key" { sensitive = true }
variable "etcd_s3_bucket" { type = string }
variable "etcd_s3_region" { type = string }
variable "etcd_s3_endpoint" { type = string }

# Manifest Versions
variable "ccm_version" { type = string }
variable "csi_version" { type = string }
variable "cilium_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "argocd_version" { type = string }

# Provider
provider "hcloud" {
  token = var.token
}

locals {
  location_zone_map = {
    "ash" = "us-east"
    "hil" = "us-west"
  }
  network_zone = local.location_zone_map[var.location]
  prefix       = "${var.cloud_env}-${local.network_zone}"

  nat_server_ip                = cidrhost("10.0.1.0/24", 254)
  k3s_api_load_balancer_ip     = cidrhost("10.0.1.0/24", 244)
  k3s_ingress_load_balancer_ip = cidrhost("10.0.1.0/24", 234)

  config = {
    dev = {
      server_count = 1,
      agent_count  = 1,
    }
    prod = {
      server_count = 3,
      agent_count  = 3,
    }
  }
  env = local.config[var.cloud_env]

  nat_user_data = templatefile("${path.module}/templates/cloud-init-nat.yaml", {
    tailscale_auth_nat_key = var.tailscale_auth_nat_key
    hostname               = "${local.prefix}-nat"
  })

  manifest_injector_script = join("\n", [
    for filename, content in module.k3s_manifests.rendered_manifests :
    "echo '${base64encode(content)}' | base64 -d > /var/lib/rancher/k3s/server/manifests/${filename}"
  ])
}

# DATA SOURCES
data "hcloud_image" "nat-gateway" {
  with_selector = "role=nat-gateway,location=${var.location}"
  most_recent   = true
}

data "hcloud_image" "k3s_node" {
  with_selector = "role=k3s-node,location=${var.location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

# NETWORK INFRASTRUCTURE
resource "hcloud_network" "main" {
  name     = "${local.prefix}-vnet"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k3s_nodes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_server" "nat" {
  name = "${local.prefix}-nat"
  # image = data.hcloud_image.ubuntu.id
  image       = data.hcloud_image.nat-gateway.id
  server_type = var.nat_gateway_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]
  labels      = { cluster = local.prefix, role = "nat" }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.nat_server_ip
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
  gateway     = local.nat_server_ip
  depends_on  = [time_sleep.wait_for_nat_config]
}

# LOAD BALANCERS
resource "hcloud_load_balancer" "api" {
  name               = "${local.prefix}-lb-api"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "api_net" {
  load_balancer_id = hcloud_load_balancer.api.id
  network_id       = hcloud_network.main.id
  ip               = local.k3s_api_load_balancer_ip
  depends_on       = [hcloud_network_subnet.k3s_nodes]
}

resource "hcloud_load_balancer_service" "k3s_api" {
  load_balancer_id = hcloud_load_balancer.api.id
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

resource "hcloud_load_balancer" "ingress" {
  name               = "${local.prefix}-lb-ingress"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "ingress_net" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  ip               = local.k3s_ingress_load_balancer_ip
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

# CLUSTER TOKENS
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# MANIFEST FACTORY: Get K8s Manifests from the Universal Module
module "k3s_manifests" {
  source = "../../modules/k3s_node"

  cloud_provider_name  = "hcloud"
  cloud_provider_mtu   = 1450
  k3s_load_balancer_ip = local.k3s_api_load_balancer_ip

  # Universal Versions
  cilium_version        = var.cilium_version
  ingress_nginx_version = var.ingress_nginx_version
  argocd_version        = var.argocd_version
  git_repo_url          = var.git_repo_url

  # Hetzner Specific Injections
  token               = var.token
  hcloud_network_name = hcloud_network.main.name
  ccm_version         = var.ccm_version
  csi_version         = var.csi_version
}

# PHASE 1: CONTROL PLANE INIT (The first server that creates the cluster)
resource "hcloud_server" "control_plane_init" {
  name        = format("${local.prefix}-k3s-sv-%02d", 1)
  image       = data.hcloud_image.k3s_node.id
  server_type = var.k3s_server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = cidrhost("10.0.1.0/24", 2)
  }


  labels = { cluster = local.prefix, role = "server" }

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname                      = format("${local.prefix}-k3s-sv-%02d", 1)
    k3s_token                     = random_password.k3s_token.result
    k3s_load_balancer_ip          = local.k3s_api_load_balancer_ip
    k3s_cluster_setting           = "cluster-init: true"
    etcd_s3_access_key            = var.etcd_s3_access_key
    etcd_s3_secret_key            = var.etcd_s3_secret_key
    etcd_s3_bucket                = var.etcd_s3_bucket
    etcd_s3_endpoint              = var.etcd_s3_endpoint
    network_gateway               = local.nat_server_ip
    tailscale_auth_k3s_server_key = var.tailscale_auth_k3s_server_key

    manifest_injector_script = local.manifest_injector_script
  })

  depends_on = [hcloud_network_route.default_route, time_sleep.wait_for_nat_config]
}


resource "hcloud_load_balancer_target" "api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = hcloud_server.control_plane_init.id
  use_private_ip   = true
}

resource "time_sleep" "wait_for_init_node" {
  depends_on      = [hcloud_server.control_plane_init, hcloud_load_balancer_target.api_target_init]
  create_duration = "120s"
}

# PHASE 2: CONTROL PLANE JOIN (Additional servers for High Availability)
resource "hcloud_server" "control_plane_join" {
  count       = local.env.server_count > 1 ? local.env.server_count - 1 : 0
  name        = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  image       = data.hcloud_image.k3s_node.id
  server_type = var.k3s_server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = cidrhost("10.0.1.0/24", count.index + 3)
  }

  labels = { cluster = local.prefix, role = "server" }

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname                      = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
    k3s_token                     = random_password.k3s_token.result
    k3s_load_balancer_ip          = local.k3s_api_load_balancer_ip
    k3s_cluster_setting           = "server: https://${local.k3s_api_load_balancer_ip}:6443"
    etcd_s3_access_key            = var.etcd_s3_access_key
    etcd_s3_secret_key            = var.etcd_s3_secret_key
    etcd_s3_bucket                = var.etcd_s3_bucket
    etcd_s3_endpoint              = var.etcd_s3_endpoint
    network_gateway               = local.nat_server_ip
    tailscale_auth_k3s_server_key = var.tailscale_auth_k3s_server_key
    manifest_injector_script      = ""
  })

  depends_on = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "api_targets_join" {
  count            = local.env.server_count > 1 ? local.env.server_count - 1 : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = hcloud_server.control_plane_join[count.index].id
  use_private_ip   = true
}

# PHASE 3: WORKER
resource "hcloud_server" "agent" {
  count       = local.env.agent_count
  name        = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  image       = data.hcloud_image.k3s_node.id
  server_type = var.k3s_agent_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = cidrhost("10.0.1.0/24", count.index + 2 + local.env.server_count)
  }


  labels = { cluster = local.prefix, role = "agent" }

  user_data = templatefile("${path.module}/templates/cloud-init-agent.yaml", {
    hostname                     = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
    k3s_token                    = random_password.k3s_token.result
    k3s_control_plane_url        = "${local.k3s_api_load_balancer_ip}:6443"
    tailscale_auth_k3s_agent_key = var.tailscale_auth_k3s_agent_key
    network_gateway              = local.nat_server_ip
  })

  depends_on = [time_sleep.wait_for_init_node, hcloud_server.control_plane_join]
}

resource "hcloud_load_balancer_target" "ingress_targets" {
  count            = local.env.agent_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress.id
  server_id        = hcloud_server.agent[count.index].id
  use_private_ip   = true
}
