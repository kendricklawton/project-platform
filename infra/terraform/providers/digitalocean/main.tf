terraform {
  required_version = ">= 1.5.0"
  backend "gcs" {}
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
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
  default = "digitalocean"
  type    = string
}


variable "token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "master_type" {
  description = "Master node type"
  type        = string
}

variable "worker_type" {
  description = "Worker node type"
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

# Manifest Versions
variable "ccm_version" { type = string }
variable "csi_version" { type = string }
variable "cilium_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "argocd_version" { type = string }

provider "digitalocean" {
  token = var.token
}

locals {
  prefix = "${var.location}-${var.cloud_env}-k3s-${var.project_name}"

  config = {
    dev  = { master_count = 1, worker_count = 1 }
    prod = { master_count = 3, worker_count = 3 }
  }
  env = local.config[var.cloud_env]
}

# INFRASTRUCTURE RESOURCES
data "digitalocean_images" "k3s_base" {
  filter {
    # FIX: Filter by the name we see in your dashboard
    key    = "name"
    values = ["${var.location}-k3s-base-v1"]
  }

  filter {
    key    = "regions"
    values = [var.location]
  }

  sort {
    key       = "created"
    direction = "desc"
  }
}

data "digitalocean_ssh_key" "admin" {
  name = var.ssh_key_name
}

# K3s NETWORK
resource "digitalocean_vpc" "k3s_main" {
  name     = "${local.prefix}-vpc"
  region   = var.location
  ip_range = "10.0.0.0/16"
}

# LOAD BALANCERS
resource "digitalocean_loadbalancer" "k3s_api" {
  name     = "${local.prefix}-lb-k3s-api"
  region   = var.location
  vpc_uuid = digitalocean_vpc.k3s_main.id

  forwarding_rule {
    entry_port      = 6443
    entry_protocol  = "tcp"
    target_port     = 6443
    target_protocol = "tcp"
  }

  healthcheck {
    protocol = "tcp"
    port     = 6443
  }

  droplet_tag = "${local.prefix}-lb-k3s-server"
}

resource "digitalocean_loadbalancer" "k3s_ingress" {
  name                  = "${local.prefix}-lb-k3s-ingress"
  region                = var.location
  vpc_uuid              = digitalocean_vpc.k3s_main.id
  enable_proxy_protocol = true

  forwarding_rule {
    entry_port      = 80
    entry_protocol  = "tcp"
    target_port     = 80
    target_protocol = "tcp"
  }

  forwarding_rule {
    entry_port      = 443
    entry_protocol  = "tcp"
    target_port     = 443
    target_protocol = "tcp"
  }

  healthcheck {
    port     = 80
    protocol = "tcp"
  }

  droplet_tag = "${local.prefix}-lb-k3s-agent"
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
  # Use the LB's private IP for Cilium bootstrap to avoid circular dependency
  k3s_api_ip = digitalocean_loadbalancer.k3s_api.private_ip

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
  cloud_provider = "digitalocean"

  # K3s
  k3s_load_balancer_ip = digitalocean_loadbalancer.k3s_api.private_ip
  k3s_token            = random_password.k3s_token.result
  k3s_init             = true
  tailscale_auth_key   = var.tailscale_auth_k3s_server_key

  # Inject Manifests (From the Module!)
  manifests = module.manifests.manifests

  # Backups
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_bucket     = var.etcd_s3_bucket
}

resource "digitalocean_droplet" "k3s_cp_init" {
  name      = format("${local.prefix}-k3s-sv-%02d", 1)
  image     = data.digitalocean_images.k3s_base.images[0].id
  region    = var.location
  size      = var.master_type
  ssh_keys  = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid  = digitalocean_vpc.k3s_main.id
  tags      = ["${local.prefix}-k3s-server", "${local.prefix}-lb-k3s-server"]
  user_data = module.config_k3s_cp_init.user_data
}

resource "time_sleep" "wait_for_init_node" {
  depends_on      = [digitalocean_droplet.k3s_cp_init]
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
  cloud_provider = "digitalocean"


  # K3s
  k3s_load_balancer_ip = digitalocean_loadbalancer.k3s_api.private_ip
  k3s_token            = random_password.k3s_token.result
  k3s_init             = false
  tailscale_auth_key   = var.tailscale_auth_k3s_server_key
  etcd_s3_access_key   = var.etcd_s3_access_key
  etcd_s3_secret_key   = var.etcd_s3_secret_key
  etcd_s3_bucket       = var.etcd_s3_bucket
}

resource "digitalocean_droplet" "cp_join" {
  count      = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  name       = format("${local.prefix}-k3s-sv-%02d", count.index + 2)
  image      = data.digitalocean_images.k3s_base.images[0].id
  region     = var.location
  size       = var.master_type
  ssh_keys   = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid   = digitalocean_vpc.k3s_main.id
  tags       = ["${local.prefix}-k3s-server", "${local.prefix}-lb-k3s-server"]
  user_data  = module.config_k3s_cp_join[count.index].user_data
  depends_on = [time_sleep.wait_for_init_node]
}

# WORKER AGENTS
module "config_worker" {
  source = "../../modules/k3s_node"
  count  = local.env.worker_count

  hostname       = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  cloud_env      = var.cloud_env
  node_role      = "agent"
  cloud_provider = "digitalocean"


  k3s_load_balancer_ip = digitalocean_loadbalancer.k3s_api.private_ip
  k3s_token            = random_password.k3s_token.result
  tailscale_auth_key   = var.tailscale_auth_k3s_agent_key
}

resource "digitalocean_droplet" "worker" {
  count      = local.env.worker_count
  name       = format("${local.prefix}-k3s-ag-%02d", count.index + 1)
  image      = data.digitalocean_images.k3s_base.images[0].id
  region     = var.location
  size       = var.worker_type
  ssh_keys   = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid   = digitalocean_vpc.k3s_main.id
  tags       = ["${local.prefix}-agent", "${local.prefix}-lb-k3s-agent"]
  user_data  = module.config_worker[count.index].user_data
  depends_on = [time_sleep.wait_for_init_node]
}

# CLOUD FIREWALL
resource "digitalocean_firewall" "k3s_hard_shell" {
  name = "${local.prefix}-hard-shell-fw"

  # Droplet Tags to apply this firewall to
  tags = [
    "${local.prefix}-k3s-server",
    "${local.prefix}-agent"
  ]

  # ALLOW: Inbound from Load Balancers
  inbound_rule {
    protocol                  = "tcp"
    port_range                = "6443"
    source_load_balancer_uids = [digitalocean_loadbalancer.k3s_api.id]
  }

  inbound_rule {
    protocol                  = "tcp"
    port_range                = "80"
    source_load_balancer_uids = [digitalocean_loadbalancer.k3s_ingress.id]
  }

  inbound_rule {
    protocol                  = "tcp"
    port_range                = "443"
    source_load_balancer_uids = [digitalocean_loadbalancer.k3s_ingress.id]
  }

  # ALLOW: WireGuard (Tailscale Mesh VPN)
  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # ALLOW: Internal VPC Traffic
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = ["10.0.0.0/16"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = ["10.0.0.0/16"]
  }

  # OUTBOUND: All Allowed (Explicitly required in DO)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "k3s_api_endpoint" {
  value = digitalocean_loadbalancer.k3s_api.ip
}

output "k3s_ingress_ip" {
  value = digitalocean_loadbalancer.k3s_ingress.ip
}

output "control_plane_ids" {
  value = concat([digitalocean_droplet.k3s_cp_init.id], digitalocean_droplet.cp_join[*].id)
}

output "worker_ids" {
  value = digitalocean_droplet.worker[*].id
}
