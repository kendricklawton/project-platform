terraform {
  required_version = ">= 1.5.0"
  backend "gcs" {}
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
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
variable "region" { type = string }       # nyc3, sfo3, ams3, etc.
variable "token" { sensitive = true }     # DigitalOcean API token
variable "ssh_key_name" { type = string }
variable "git_repo_url" { type = string }

# Droplet sizes (DigitalOcean slug format)
variable "cp_server_type" { type = string }
variable "worker_server_type" { type = string }
variable "load_balancer_type" { type = string }   # lb-small, lb-medium

# Tailscale
variable "tailscale_auth_nat_key" { sensitive = true }
variable "tailscale_auth_cp_key" { sensitive = true }
variable "tailscale_auth_worker_key" { sensitive = true }

# NAT gateway droplet size
variable "nat_gateway_type" {
  type    = string
  default = "s-1vcpu-1gb"
}

# Kubernetes + addons
variable "kubernetes_version" { type = string }
variable "cilium_version" { type = string }
variable "argocd_version" { type = string }
variable "sealed_secrets_version" { type = string }
variable "ccm_version" { type = string }      # digitalocean-cloud-controller-manager chart version
variable "csi_version" { type = string }      # csi-digitalocean chart version
variable "ingress_nginx_version" { type = string }
variable "cluster_mtu" {
  type    = number
  default = 1500  # Standard MTU — no overlay reduction needed on DO VPC
}

provider "digitalocean" {
  token = var.token
}

locals {
  # Pattern: {env}-{region}-{type}[-{role}][-{index}]
  prefix = "${var.env}-${var.region}"

  # Tag names scoped to this cluster prefix
  cp_tag     = "${local.prefix}-cp"
  worker_tag = "${local.prefix}-worker"

  # Cluster size per environment
  cluster_config = {
    dev  = { cp_count = 1, worker_count = 1 }
    prod = { cp_count = 3, worker_count = 3 }
  }

  cp_count     = local.cluster_config[var.env].cp_count
  worker_count = local.cluster_config[var.env].worker_count

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

resource "random_id" "kubeadm_cert_key" {
  byte_length = 32
}

# --- DATA SOURCES ---
data "digitalocean_ssh_key" "admin" {
  name = var.ssh_key_name
}

# K8s node snapshot — built by Packer, tagged role:k8s-node
data "digitalocean_droplet_snapshot" "k8s_node" {
  name_regex  = "^${var.region}-k8s-node-ubuntu-amd64"
  region      = var.region
  most_recent = true
}

# --- VPC ---
# DO VPC is a flat network (no subnet hierarchy). All droplets share the CIDR.
resource "digitalocean_vpc" "main" {
  name     = "${local.prefix}-vpc"
  region   = var.region
  ip_range = "10.0.0.0/20"
}

# --- NAT GATEWAY ---
# Provides a consistent egress IP for all cluster traffic.
# Uses the base Ubuntu image (no K8s packages needed) — cloud-init installs iptables.
resource "digitalocean_droplet" "nat" {
  name     = "${local.prefix}-nat"
  region   = var.region
  size     = var.nat_gateway_type
  image    = "ubuntu-24-04-x64"   # base image — cloud-init handles everything
  ssh_keys = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid = digitalocean_vpc.main.id
  tags     = [local.prefix]

  user_data = templatefile("${path.module}/templates/cloud-init-nat.yaml", {
    hostname               = "${local.prefix}-nat"
    tailscale_auth_nat_key = var.tailscale_auth_nat_key
  })
}

resource "time_sleep" "wait_for_nat" {
  depends_on      = [digitalocean_droplet.nat]
  create_duration = "90s"   # wait for NAT iptables + Tailscale to come up before nodes boot
}

# --- LOAD BALANCERS ---
# Created before droplets so their IPs are known for kubeadm certSANs/endpoint.
# DO LBs target droplets by tag — droplets must carry the matching tag.

resource "digitalocean_loadbalancer" "api" {
  name       = "${local.prefix}-lb-api"
  region     = var.region
  size       = var.load_balancer_type
  vpc_uuid   = digitalocean_vpc.main.id
  droplet_tag = local.cp_tag

  forwarding_rule {
    entry_port      = 6443
    entry_protocol  = "tcp"
    target_port     = 6443
    target_protocol = "tcp"
  }

  healthcheck {
    port     = 6443
    protocol = "tcp"
  }
}

resource "digitalocean_loadbalancer" "ingress" {
  name        = "${local.prefix}-lb-ingress"
  region      = var.region
  size        = var.load_balancer_type
  vpc_uuid    = digitalocean_vpc.main.id
  droplet_tag = local.worker_tag

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
    tls_passthrough = true
  }

  healthcheck {
    port     = 80
    protocol = "tcp"
  }

  enable_proxy_protocol = true
}

# --- PHASE 1: CONTROL PLANE INIT ---
resource "digitalocean_droplet" "control_plane_init" {
  name     = "${local.prefix}-server-cp-01"
  region   = var.region
  size     = var.cp_server_type
  image    = data.digitalocean_droplet_snapshot.k8s_node.id
  ssh_keys = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid = digitalocean_vpc.main.id
  # Tags must include local.cp_tag so the API LB targets this droplet
  tags     = [local.cp_tag]

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname               = "${local.prefix}-server-cp-01"
    network_gateway        = digitalocean_droplet.nat.ipv4_address_private
    kubernetes_api_lb_ip   = digitalocean_loadbalancer.api.ip
    kubeadm_token          = local.kubeadm_token
    kubeadm_cert_key       = random_id.kubeadm_cert_key.hex
    is_init_node           = true
    tailscale_auth_cp_key  = var.tailscale_auth_cp_key
    git_repo_url           = var.git_repo_url
    cilium_version         = var.cilium_version
    cluster_mtu            = var.cluster_mtu
    argocd_version         = var.argocd_version
    do_token               = var.token
    ccm_version            = var.ccm_version
    csi_version            = var.csi_version
    ingress_nginx_version  = var.ingress_nginx_version
    sealed_secrets_version = var.sealed_secrets_version
  })

  depends_on = [digitalocean_loadbalancer.api, time_sleep.wait_for_nat]
}

# --- PHASE 2: CONTROL PLANE JOIN ---
resource "digitalocean_droplet" "control_plane_join" {
  count    = local.cp_count - 1
  name     = format("${local.prefix}-server-cp-%02d", count.index + 2)
  region   = var.region
  size     = var.cp_server_type
  image    = data.digitalocean_droplet_snapshot.k8s_node.id
  ssh_keys = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid = digitalocean_vpc.main.id
  tags     = [local.cp_tag]

  user_data = templatefile("${path.module}/templates/cloud-init-server.yaml", {
    hostname               = format("${local.prefix}-server-cp-%02d", count.index + 2)
    network_gateway        = digitalocean_droplet.nat.ipv4_address_private
    kubernetes_api_lb_ip   = digitalocean_loadbalancer.api.ip
    kubeadm_token          = local.kubeadm_token
    kubeadm_cert_key       = random_id.kubeadm_cert_key.hex
    is_init_node           = false
    tailscale_auth_cp_key  = var.tailscale_auth_cp_key
    git_repo_url           = var.git_repo_url
    cilium_version         = var.cilium_version
    cluster_mtu            = var.cluster_mtu
    argocd_version         = var.argocd_version
    do_token               = var.token
    ccm_version            = var.ccm_version
    csi_version            = var.csi_version
    ingress_nginx_version  = var.ingress_nginx_version
    sealed_secrets_version = var.sealed_secrets_version
  })

  depends_on = [digitalocean_droplet.control_plane_init]
}

# --- PHASE 3: WORKERS ---
resource "digitalocean_droplet" "worker" {
  count    = local.worker_count
  name     = format("${local.prefix}-server-wk-%02d", count.index + 1)
  region   = var.region
  size     = var.worker_server_type
  image    = data.digitalocean_droplet_snapshot.k8s_node.id
  ssh_keys = [data.digitalocean_ssh_key.admin.id]
  vpc_uuid = digitalocean_vpc.main.id
  # Tags must include local.worker_tag so the ingress LB targets this droplet
  tags     = [local.worker_tag]

  user_data = templatefile("${path.module}/templates/cloud-init-agent.yaml", {
    hostname                  = format("${local.prefix}-server-wk-%02d", count.index + 1)
    network_gateway           = digitalocean_droplet.nat.ipv4_address_private
    kubernetes_api_lb_ip      = digitalocean_loadbalancer.api.ip
    kubeadm_token             = local.kubeadm_token
    tailscale_auth_worker_key = var.tailscale_auth_worker_key
  })

  depends_on = [digitalocean_droplet.control_plane_init]
}
