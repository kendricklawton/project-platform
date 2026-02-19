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

# PROVIDERS
provider "hcloud" {
  token = var.token
}

# LOCALS
locals {
  # --- 1. GLOBAL IDENTIFIERS ---
  prefix = "${var.location}-${var.cloud_env}"

  # --- 2. CLUSTER TOPOLOGY ---
  cluster_profiles = {
    dev  = { master_count = 1, worker_count = 1, operator_replicas = 1 }
    prod = { master_count = 3, worker_count = 3, operator_replicas = 2 }
  }
  cluster_env = local.cluster_profiles[var.cloud_env]

  # --- 3. NETWORK CONFIGURATION ---
  net_nodes_cidr = cidrsubnet(var.vpc_cidr, 8, 1) # Results in 10.10.1.0/24

  net_zone_map = {
    ash  = "us-east"
    hil  = "us-west"
    nbg1 = "eu-central"
    fsn1 = "eu-central"
    hel1 = "eu-central"
  }
  net_zone = local.net_zone_map[var.location]

  # --- 4. STATIC ROUTING IPs ---
  ip_api_lb     = hcloud_load_balancer_network.api_lb_net.ip
  ip_ingress_lb = hcloud_load_balancer_network.ingress_lb_net.ip
  ip_cp_init    = cidrhost(local.net_nodes_cidr, 10)
}

# PASSWORD/TOKEN GENERATION
resource "random_password" "token" {
  length  = 32
  special = false
}

# DATA SOURCES
data "hcloud_image" "nat" {
  with_selector = "role=nat-gateway,location=${var.location}"
  most_recent   = true
}

data "hcloud_image" "k3s" {
  with_selector = "role=k3s-node,location=${var.location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

# SHARED BRAIN (MANIFESTS)
module "manifests" {
  source = "../../modules/k3s_cluster"

  cloud_provider    = var.cloud_provider
  cloud_env         = var.cloud_env
  project_name      = var.project_name
  operator_replicas = local.cluster_env.operator_replicas
  # vpc_cidr          = var.vpc_cidr
  private_interface = var.private_interface

  # network_mtu       = var.network_mtu

  api_ip  = local.ip_cp_init
  network = hcloud_network.main.name
  token   = var.token

  github_repo_url = var.github_repo_url

  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_endpoint   = var.etcd_s3_endpoint
  etcd_s3_region     = var.etcd_s3_region

  ccm_version           = var.ccm_version
  csi_version           = var.csi_version
  cilium_version        = var.cilium_version
  ingress_nginx_version = var.ingress_nginx_version
  argocd_version        = var.argocd_version
}

# CONTROL PLANE INIT
module "config_cp_init" {
  source = "../../modules/k3s_node"

  hostname  = format("${local.prefix}-k3s-sv-%02d", 1)
  cloud_env = var.cloud_env
  node_role = "server"

  cloud_provider = var.cloud_provider

  k3s_api_lb_ip      = local.ip_api_lb
  k3s_token          = random_password.token.result
  k3s_init           = true
  tailscale_auth_key = var.tailscale_auth_k3s_server_key
  network_gateway    = var.network_gateway

  manifests = module.manifests.manifests

  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_region     = var.etcd_s3_region
  etcd_s3_endpoint   = var.etcd_s3_endpoint
}

resource "hcloud_server" "cp_init" {
  name        = format("${local.prefix}-k3s-sv-%02d", 1)
  image       = data.hcloud_image.k3s.id
  server_type = var.master_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
  }

  depends_on = [hcloud_network_subnet.k3s_nodes]

  labels = {
    cluster = local.prefix
    role    = "server"
  }

  user_data = base64gzip(module.config_cp_init.user_data)
}

resource "hcloud_load_balancer_target" "api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  server_id        = hcloud_server.cp_init.id
  use_private_ip   = true
}

resource "time_sleep" "wait_for_init_node" {
  depends_on      = [hcloud_server.cp_init]
  create_duration = "120s"
}

# CONTROL PLANE JOIN
module "config_k3s_cp_join" {
  source    = "../../modules/k3s_node"
  count     = local.cluster_env.master_count > 1 ? local.cluster_env.master_count - 1 : 0
  hostname  = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  cloud_env = var.cloud_env
  node_role = "server"

  cloud_provider  = var.cloud_provider
  network_gateway = var.network_gateway

  k3s_api_lb_ip      = local.ip_api_lb
  k3s_ingress_lb_ip  = local.ip_ingress_lb
  k3s_token          = random_password.token.result
  k3s_init           = false
  tailscale_auth_key = var.tailscale_auth_k3s_server_key
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_region     = var.etcd_s3_region
  etcd_s3_endpoint   = var.etcd_s3_endpoint
}

resource "hcloud_server" "cp_join" {
  count       = local.cluster_env.master_count > 1 ? local.cluster_env.master_count - 1 : 0
  name        = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  image       = data.hcloud_image.k3s.id
  server_type = var.master_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
  }

  labels = {
    cluster = local.prefix
    role    = "server"
  }

  user_data  = base64gzip(module.config_k3s_cp_join[count.index].user_data)
  depends_on = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "api_targets_join" {
  count            = local.cluster_env.master_count > 1 ? local.cluster_env.master_count - 1 : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  server_id        = hcloud_server.cp_join[count.index].id
  use_private_ip   = true
}

# WORKER AGENTS
module "config_k3s_agent" {
  source = "../../modules/k3s_node"
  count  = local.cluster_env.worker_count

  hostname           = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  cloud_env          = var.cloud_env
  node_role          = "agent"
  cloud_provider     = var.cloud_provider
  k3s_api_lb_ip      = local.ip_api_lb
  k3s_token          = random_password.token.result
  tailscale_auth_key = var.tailscale_auth_k3s_agent_key
}

resource "hcloud_server" "worker" {
  count       = local.cluster_env.worker_count
  name        = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  image       = data.hcloud_image.k3s.id
  server_type = var.worker_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.main.id
  }

  labels = {
    cluster = local.prefix
    role    = "agent"
  }

  user_data  = base64gzip(module.config_k3s_agent[count.index].user_data)
  depends_on = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "ingress_targets" {
  count            = local.cluster_env.worker_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  server_id        = hcloud_server.worker[count.index].id
  use_private_ip   = true
}

# FIREWALL
resource "hcloud_firewall" "cluster_fw" {
  name = "${local.prefix}-fw-${var.location}"

  # --- 1. PUBLIC INGRESS (Restricted) ---
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["${local.ip_api_lb}/32"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "${local.ip_ingress_lb}/32",
      var.vpc_cidr
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "${local.ip_ingress_lb}/32",
      var.vpc_cidr
    ]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # --- 2. INTERNAL TRUST (VPC) ---
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = [var.vpc_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = [var.vpc_cidr]
  }

  # --- 3. HARDENED EGRESS (Outbound) ---
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "123"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "41641"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "3478"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  # --- 4. TARGETS ---
  apply_to {
    label_selector = "cluster=${local.prefix}"
  }
}
