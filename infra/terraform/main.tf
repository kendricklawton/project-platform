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
variable "env" { type = string }          # dev | prod
variable "region" { type = string }       # plain string: eu-central, us-east, etc.
variable "token" { sensitive = true }
variable "ssh_key_name" { type = string }
variable "location" { type = string }     # Hetzner datacenter code: nbg1, fsn1, hel1, ash, hil

# Server Types
variable "cp_server_type" { type = string }
variable "worker_server_type" { type = string }
variable "nat_gateway_type" { type = string }
variable "load_balancer_type" { type = string }
variable "git_repo_url" { type = string }

# Tailscale
variable "tailscale_auth_nat_key" { sensitive = true }
variable "tailscale_auth_cp_key" { sensitive = true }
variable "tailscale_auth_worker_key" { sensitive = true }

# Kubernetes
variable "kubernetes_version" { type = string }
variable "cilium_version" { type = string }
variable "argocd_version" { type = string }
variable "sealed_secrets_version" { type = string }

# Hetzner cloud integration
variable "ccm_version" { type = string }
variable "csi_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "hcloud_mtu" {
  type    = number
  default = 1450
}

provider "hcloud" {
  token = var.token
}

locals {
  # {env}-{region} — both are plain input variables, no provider-specific derivation.
  # Pattern: {env}-{region}-{type}[-{role}][-{index}]
  # Examples: dev-eu-central-server-cp-01, prod-us-east-lb-api
  prefix = "${var.env}-${var.region}"

  # Infrastructure IPs
  nat_server_ip            = cidrhost("10.0.1.0/24", 2)
  api_load_balancer_ip     = cidrhost("10.0.1.0/24", 11)
  ingress_load_balancer_ip = cidrhost("10.0.1.0/24", 12)

  # Cluster size per environment
  cluster_config = {
    dev  = { cp_count = 1, worker_count = 1 }
    prod = { cp_count = 3, worker_count = 3 }
  }

  # Sticky name→IP maps for the recycle method
  cp_map = {
    for i in range(local.cluster_config[var.env].cp_count) :
    format("${local.prefix}-server-cp-%02d", i + 1) => cidrhost("10.0.1.0/24", i + 21)
  }

  worker_map = {
    for i in range(local.cluster_config[var.env].worker_count) :
    format("${local.prefix}-server-wk-%02d", i + 1) => cidrhost("10.0.1.0/24", i + 31)
  }

  # Split init control plane from join control planes
  init_cp_name = format("${local.prefix}-server-cp-%02d", 1)
  join_cps     = { for k, v in local.cp_map : k => v if k != local.init_cp_name }

  # kubeadm bootstrap token: [a-z0-9]{6}.[a-z0-9]{16}
  kubeadm_token = "${random_string.kubeadm_token_id.result}.${random_string.kubeadm_token_secret.result}"
}

# --- KUBEADM TOKENS ---
resource "random_string" "kubeadm_token_id" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "kubeadm_token_secret" {
  length  = 16
  upper   = false
  special = false
}

# Certificate key for HA control-plane join (32-byte hex)
resource "random_id" "kubeadm_cert_key" {
  byte_length = 32
}

# --- DATA SOURCES ---
data "hcloud_image" "nat_gateway" {
  with_selector = "role=nat-gateway,location=${var.location}"
  most_recent   = true
}

data "hcloud_image" "k8s_node" {
  with_selector = "role=k8s-node,location=${var.location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

# --- NETWORK ---
resource "hcloud_network" "main" {
  name     = "${local.prefix}-net"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k8s_nodes" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = var.region  # Hetzner network zone — matches var.region (eu-central, us-east, us-west, ap-southeast)
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_server" "nat" {
  name        = "${local.prefix}-nat"
  image       = data.hcloud_image.nat_gateway.id
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

  user_data = templatefile("${path.module}/templates/cloud-init-nat.yaml", {
    tailscale_auth_nat_key = var.tailscale_auth_nat_key
    hostname               = "${local.prefix}-nat"
  })
}

resource "time_sleep" "wait_for_nat_config" {
  depends_on      = [hcloud_server.nat]
  create_duration = "60s"
}

resource "hcloud_network_route" "default_route" {
  network_id  = hcloud_network.main.id
  destination = "0.0.0.0/0"
  gateway     = local.nat_server_ip
  depends_on  = [time_sleep.wait_for_nat_config]
}

# --- LOAD BALANCERS ---
resource "hcloud_load_balancer" "api" {
  name               = "${local.prefix}-lb-api"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "api_net" {
  load_balancer_id = hcloud_load_balancer.api.id
  network_id       = hcloud_network.main.id
  ip               = local.api_load_balancer_ip
}

resource "hcloud_load_balancer_service" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443
}

resource "hcloud_load_balancer" "ingress" {
  name               = "${local.prefix}-lb-ingress"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "ingress_net" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  ip               = local.ingress_load_balancer_ip
  network_id       = hcloud_network.main.id
}

# --- PHASE 1: CONTROL PLANE INIT ---
resource "hcloud_server" "control_plane_init" {
  name        = local.init_cp_name
  image       = data.hcloud_image.k8s_node.id
  server_type = var.cp_server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.cp_map[local.init_cp_name]
  }

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname              = local.init_cp_name
    node_private_ip       = local.cp_map[local.init_cp_name]
    network_gateway       = local.nat_server_ip
    kubernetes_api_lb_ip  = local.api_load_balancer_ip
    kubeadm_token         = local.kubeadm_token
    kubeadm_cert_key      = random_id.kubeadm_cert_key.hex
    is_init_node          = true
    tailscale_auth_cp_key = var.tailscale_auth_cp_key
    git_repo_url          = var.git_repo_url
    cilium_version        = var.cilium_version
    hcloud_mtu            = var.hcloud_mtu
    argocd_version        = var.argocd_version
    hcloud_token          = var.token
    hcloud_network_name   = hcloud_network.main.name
    ccm_version           = var.ccm_version
    csi_version           = var.csi_version
    ingress_nginx_version = var.ingress_nginx_version
    sealed_secrets_version = var.sealed_secrets_version
  })

  depends_on = [hcloud_network_route.default_route]
}

resource "hcloud_load_balancer_target" "api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = hcloud_server.control_plane_init.id
  use_private_ip   = true
}

# --- PHASE 2: CONTROL PLANE JOIN (RECYCLE READY) ---
resource "hcloud_server" "control_plane_join" {
  for_each    = local.join_cps
  name        = each.key
  image       = data.hcloud_image.k8s_node.id
  server_type = var.cp_server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = each.value
  }

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname              = each.key
    node_private_ip       = each.value
    network_gateway       = local.nat_server_ip
    kubernetes_api_lb_ip  = local.api_load_balancer_ip
    kubeadm_token         = local.kubeadm_token
    kubeadm_cert_key      = random_id.kubeadm_cert_key.hex
    is_init_node          = false
    tailscale_auth_cp_key = var.tailscale_auth_cp_key
    git_repo_url          = var.git_repo_url
    cilium_version        = var.cilium_version
    hcloud_mtu            = var.hcloud_mtu
    argocd_version        = var.argocd_version
    hcloud_token          = var.token
    hcloud_network_name   = hcloud_network.main.name
    ccm_version           = var.ccm_version
    csi_version           = var.csi_version
    ingress_nginx_version = var.ingress_nginx_version
    sealed_secrets_version = var.sealed_secrets_version
  })

  depends_on = [hcloud_server.control_plane_init]
}

resource "hcloud_load_balancer_target" "api_targets_join" {
  for_each         = hcloud_server.control_plane_join
  type             = "server"
  load_balancer_id = hcloud_load_balancer.api.id
  server_id        = each.value.id
  use_private_ip   = true
}

# --- PHASE 3: WORKERS (RECYCLE READY) ---
resource "hcloud_server" "worker" {
  for_each    = local.worker_map
  name        = each.key
  image       = data.hcloud_image.k8s_node.id
  server_type = var.worker_server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
    ip         = each.value
  }

  user_data = templatefile("${path.module}/templates/cloud-init-agent.yaml", {
    hostname                  = each.key
    network_gateway           = local.nat_server_ip
    kubernetes_api_lb_ip      = local.api_load_balancer_ip
    kubeadm_token             = local.kubeadm_token
    tailscale_auth_worker_key = var.tailscale_auth_worker_key
  })

  depends_on = [hcloud_server.control_plane_init]
}

resource "hcloud_load_balancer_target" "ingress_targets" {
  for_each         = hcloud_server.worker
  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress.id
  server_id        = each.value.id
  use_private_ip   = true
}

resource "hcloud_load_balancer_service" "ingress_http" {
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

resource "hcloud_load_balancer_service" "ingress_https" {
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
