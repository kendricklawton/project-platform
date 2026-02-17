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
variable "cloud_provider" {
  default = "hetzner"
  type    = string
}

variable "token" {
  type      = string
  sensitive = true
}

variable "master_type" {
  description = "Master node type"
  type        = string
}

variable "worker_type" {
  description = "Worker node type"
  type        = string
}

variable "load_balancer_type" {
  description = "Load Balancer type"
  type        = string
}

variable "location" {
  type = string
}

variable "project_name" {
  type = string
}

variable "cloud_env" {
  type = string
}

variable "ssh_key_name" {
  type = string
}

variable "github_repo_url" {
  description = "The Git repository URL for Argo CD to sync from"
  type        = string
}

variable "tailscale_auth_k3s_server_key" {
  type      = string
  sensitive = true
}

variable "tailscale_auth_k3s_agent_key" {
  type      = string
  sensitive = true
}

variable "etcd_s3_bucket" {
  type = string
}

variable "etcd_s3_access_key" {
  type      = string
  sensitive = true
}

variable "etcd_s3_secret_key" {
  type      = string
  sensitive = true
}

variable "etcd_s3_endpoint" {
  type = string
}

variable "etcd_s3_region" {
  type = string
}

variable "network_gateway" {
  type        = string
  description = "The gateway IP for Hetzner networking"
  default     = "10.0.0.1"
}

# Manifest Versions
variable "ccm_version" {
  type = string
}

variable "csi_version" {
  type = string
}

variable "cilium_version" {
  type = string
}
variable "ingress_nginx_version" {
  type = string
}

variable "argocd_version" {
  type = string
}

provider "hcloud" {
  token = var.token
}

locals {
  prefix = "${var.location}-${var.cloud_env}"

  # Dynamic IP calculation to prevent circular dependencies
  nodes_cidr        = "10.0.1.0/24"
  k3s_init_node_ip  = cidrhost(local.nodes_cidr, 254) # 10.0.1.254
  k3s_api_lb_ip     = cidrhost(local.nodes_cidr, 253) # 10.0.1.253
  k3s_ingress_lb_ip = cidrhost(local.nodes_cidr, 252) # 10.0.1.252


  config = {
    dev  = { master_count = 1, worker_count = 1 }
    prod = { master_count = 3, worker_count = 3 }
  }
  env = local.config[var.cloud_env]

  network_zone_map = {
    ash  = "us-east"
    hil  = "us-west"
    nbg1 = "eu-central"
    fsn1 = "eu-central"
    hel1 = "eu-central"
  }
  network_zone = local.network_zone_map[var.location]
}

# INFRASTRUCTURE RESOURCES
data "hcloud_image" "k3s_base" {
  with_selector = "role=k3s-base,location=${var.location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

# K3s NETWORK
resource "hcloud_network" "k3s_main" {
  name     = "${local.prefix}-k3s-vnet"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "k3s_nodes" {
  network_id   = hcloud_network.k3s_main.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = local.nodes_cidr
}

# LOAD BALANCERS
resource "hcloud_load_balancer" "k3s_api" {
  name               = "${local.prefix}-k3s-lb-api"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "k3s_api_net" {
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  network_id       = hcloud_network.k3s_main.id
  ip               = local.k3s_api_lb_ip
  depends_on       = [hcloud_network_subnet.k3s_nodes]
}

resource "hcloud_load_balancer_service" "k3s_api" {
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
  name               = "${local.prefix}-k3s-lb-ingress"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "k3s_ingress_net" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  network_id       = hcloud_network.k3s_main.id
  ip               = local.k3s_ingress_lb_ip
  depends_on       = [hcloud_network_subnet.k3s_nodes]
}

resource "hcloud_load_balancer_service" "k3s_http" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
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

resource "hcloud_load_balancer_service" "k3s_https" {
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
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

# SHARED BRAIN (MANIFESTS)
module "manifests" {
  source = "../../modules/cluster"

  # Context
  cloud_provider = var.cloud_provider
  cloud_env      = var.cloud_env
  project_name   = var.project_name

  # Use the init node IP for Cilium bootstrap to avoid LB deadlock
  k3s_api_ip  = local.k3s_init_node_ip
  k3s_network = hcloud_network.k3s_main.name

  # Auth
  token = var.token

  # GitHub
  github_repo_url = var.github_repo_url

  # ETCD Backend
  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_endpoint   = var.etcd_s3_endpoint
  etcd_s3_region     = var.etcd_s3_region

  # Versions
  ccm_version           = var.ccm_version
  csi_version           = var.csi_version
  cilium_version        = var.cilium_version
  ingress_nginx_version = var.ingress_nginx_version
  argocd_version        = var.argocd_version
}

# CONTROL PLANE INIT
module "config_k3s_cp_init" {
  source = "../../modules/k3s_node"

  hostname  = format("${local.prefix}-k3s-sv-%02d", 1)
  cloud_env = var.cloud_env
  node_role = "server"

  # Provider Specifics
  cloud_provider = var.cloud_provider

  # K3s
  k3s_load_balancer_ip = local.k3s_api_lb_ip
  k3s_token            = random_password.k3s_token.result
  k3s_init             = true
  tailscale_auth_key   = var.tailscale_auth_k3s_server_key
  network_gateway      = var.network_gateway

  # Inject Manifests
  manifests = module.manifests.manifests

  # Backups
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_region     = var.etcd_s3_region
  etcd_s3_endpoint   = var.etcd_s3_endpoint
}

resource "hcloud_server" "k3s_cp_init" {
  name        = format("${local.prefix}-k3s-sv-%02d", 1)
  image       = data.hcloud_image.k3s_base.id
  server_type = var.master_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.k3s_main.id
    ip         = local.k3s_init_node_ip
  }

  depends_on = [hcloud_network_subnet.k3s_nodes]

  labels = {
    cluster = local.prefix
    role    = "server"
  }

  user_data = base64gzip(module.config_k3s_cp_init.user_data)
}

resource "hcloud_load_balancer_target" "k3s_api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  server_id        = hcloud_server.k3s_cp_init.id
  use_private_ip   = true
}

resource "time_sleep" "wait_for_init_node" {
  depends_on      = [hcloud_server.k3s_cp_init]
  create_duration = "120s"
}

# CONTROL PLANE JOIN
module "config_k3s_cp_join" {
  source    = "../../modules/k3s_node"
  count     = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  hostname  = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  cloud_env = var.cloud_env
  node_role = "server"

  # Provider Specifics
  cloud_provider  = var.cloud_provider
  network_gateway = var.network_gateway

  # K3s
  k3s_load_balancer_ip = local.k3s_api_lb_ip
  k3s_token            = random_password.k3s_token.result
  k3s_init             = false
  tailscale_auth_key   = var.tailscale_auth_k3s_server_key
  etcd_s3_access_key   = var.etcd_s3_access_key
  etcd_s3_secret_key   = var.etcd_s3_secret_key
  etcd_s3_bucket       = var.etcd_s3_bucket
  etcd_s3_region       = var.etcd_s3_region
  etcd_s3_endpoint     = var.etcd_s3_endpoint
}

resource "hcloud_server" "cp_join" {
  count       = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  name        = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  image       = data.hcloud_image.k3s_base.id
  server_type = var.master_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.k3s_main.id
  }

  labels = {
    cluster = local.prefix
    role    = "server"
  }

  user_data  = base64gzip(module.config_k3s_cp_join[count.index].user_data)
  depends_on = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "k3s_api_targets_join" {
  count            = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_api.id
  server_id        = hcloud_server.cp_join[count.index].id
  use_private_ip   = true
}

# WORKER AGENTS
module "config_worker" {
  source = "../../modules/k3s_node"
  count  = local.env.worker_count

  hostname             = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  cloud_env            = var.cloud_env
  node_role            = "agent"
  cloud_provider       = var.cloud_provider
  k3s_load_balancer_ip = local.k3s_api_lb_ip
  k3s_token            = random_password.k3s_token.result
  tailscale_auth_key   = var.tailscale_auth_k3s_agent_key
}

resource "hcloud_server" "worker" {
  count       = local.env.worker_count
  name        = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  image       = data.hcloud_image.k3s_base.id
  server_type = var.worker_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.k3s_main.id
  }

  labels = {
    cluster = local.prefix
    role    = "agent"
  }

  user_data  = base64gzip(module.config_worker[count.index].user_data)
  depends_on = [time_sleep.wait_for_init_node]
}

resource "hcloud_load_balancer_target" "k3s_ingress_targets" {
  count            = local.env.worker_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k3s_ingress.id
  server_id        = hcloud_server.worker[count.index].id
  use_private_ip   = true
}

# FIREWALL
resource "hcloud_firewall" "cluster_fw" {
  name = "${local.prefix}-fw-${var.location}"

  # ALLOW: Inbound from API Load Balancer
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["${local.k3s_api_lb_ip}/32"]
  }

  # REFACTOR: Dynamic Ingress LB isolation
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["${hcloud_load_balancer_network.k3s_ingress_net.ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["${hcloud_load_balancer_network.k3s_ingress_net.ip}/32"]
  }

  # MESH VPN: WireGuard traffic
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # INTERNAL VPC TRUST
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = ["10.0.0.0/16"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = ["10.0.0.0/16"]
  }

  # EGRESS
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  apply_to {
    label_selector = "cluster=${local.prefix}"
  }
}

output "k3s_api_endpoint" {
  value = local.k3s_api_lb_ip
}

output "k3s_ingress_ip" {
  value = hcloud_load_balancer.k3s_ingress.ipv4
}

output "control_plane_ids" {
  value = concat([hcloud_server.k3s_cp_init.id], hcloud_server.cp_join[*].id)
}

output "worker_ids" {
  value = hcloud_server.worker[*].id
}

output "control_plane_ips" {
  value = [hcloud_server.k3s_cp_init.ipv4_address]
}

output "worker_ips_list" {
  value = hcloud_server.worker[*].ipv4_address
}
