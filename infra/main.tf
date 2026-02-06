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

# --- VARIABLES ---
variable "hcloud_token" { sensitive = true }
# REMOVED: tailscale_auth_nat_key
variable "tailscale_auth_k3s_server_key" { sensitive = true }
variable "tailscale_auth_k3s_agent_key" { sensitive = true }
variable "etcd_s3_access_key" { sensitive = true }
variable "etcd_s3_secret_key" { sensitive = true }
variable "etcd_s3_bucket" { type = string }
variable "registry_s3_access_key" { sensitive = true }
variable "registry_s3_secret_key" { sensitive = true }
variable "registry_s3_bucket" { type = string }
variable "logs_s3_bucket" { type = string }
variable "logs_s3_access_key" { sensitive = true }
variable "logs_s3_secret_key" { sensitive = true }
variable "project_name" { type = string }
variable "cloud_env" { type = string }
variable "ssh_key_name" { type = string }
variable "letsencrypt_email" { type = string }
variable "gcp_project_id" { type = string }
variable "hcloud_location" { type = string }
variable "registry_htpasswd" { sensitive = true }

# Manifest Versions
variable "hcloud_ccm_version" { type = string }
variable "hcloud_csi_version" { type = string }
variable "cilium_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "cert_manager_version" { type = string }
variable "nats_version" { type = string }
variable "kubearmor_version" { type = string }
variable "kyverno_version" { type = string }
variable "fluent_bit_version" { type = string }
variable "victoria_metrics_version" { type = string }
variable "loki_version" { type = string }
variable "grafana_version" { type = string }
variable "argocd_version" { type = string }
variable "knative_version" { type = string }

# Default Values
variable "api_load_balancer_ip" {
  description = "Static internal IP for the API Server (Control Plane)"
  default     = "10.0.1.254"
}

# REMOVED: nat_hcloud_server_network_ip

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

  # Server types to match Packer builds
  config = {
    dev = {
      master_count = 1,
      worker_count = 1,
      # REMOVED: nat_type
      master_type = "cpx21",
      worker_type = "cpx21"
    }
    prod = {
      master_count = 3,
      worker_count = 3,
      # REMOVED: nat_type
      master_type = "cpx21",
      worker_type = "cpx21"
    }
  }
  env = local.config[var.cloud_env]

  # REMOVED: nat_user_data
}

# Retrieve K3s Base Image (Role=k3s-base)
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
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
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

# k3s_init = true: Creates the cluster
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
  etcd_s3_access_key        = var.etcd_s3_access_key
  etcd_s3_secret_key        = var.etcd_s3_secret_key
  etcd_s3_bucket            = var.etcd_s3_bucket
  registry_s3_access_key    = var.registry_s3_access_key
  registry_s3_secret_key    = var.registry_s3_secret_key
  registry_s3_bucket        = var.registry_s3_bucket
  logs_s3_access_key        = var.logs_s3_access_key
  logs_s3_secret_key        = var.logs_s3_secret_key
  logs_s3_bucket            = var.logs_s3_bucket
  registry_htpasswd         = var.registry_htpasswd
  victoria_metrics_version  = var.victoria_metrics_version
  loki_version              = var.loki_version
  grafana_version           = var.grafana_version
  hcloud_ccm_version        = var.hcloud_ccm_version
  hcloud_csi_version        = var.hcloud_csi_version
  cilium_version            = var.cilium_version
  ingress_nginx_version     = var.ingress_nginx_version
  cert_manager_version      = var.cert_manager_version
  nats_version              = var.nats_version
  kubearmor_version         = var.kubearmor_version
  kyverno_version           = var.kyverno_version
  fluent_bit_version        = var.fluent_bit_version
  argocd_version            = var.argocd_version
  knative_version           = var.knative_version
  # REMOVED: depends_on = [hcloud_network_route.default_route, time_sleep.wait_for_nat_config]
  # No dependencies on NAT anymore
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

# k3s_init = false: Joins the existing cluster
module "control_plane_join" {
  node_role                 = "server"
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
  k3s_token                 = random_password.k3s_token.result
  load_balancer_ip          = var.api_load_balancer_ip
  k3s_init                  = false
  tailscale_auth_server_key = var.tailscale_auth_k3s_server_key
  hcloud_token              = var.hcloud_token
  hcloud_network_name       = hcloud_network.main.name
  etcd_s3_access_key        = var.etcd_s3_access_key
  etcd_s3_secret_key        = var.etcd_s3_secret_key
  etcd_s3_bucket            = var.etcd_s3_bucket
  registry_s3_access_key    = var.registry_s3_access_key
  registry_s3_secret_key    = var.registry_s3_secret_key
  registry_s3_bucket        = var.registry_s3_bucket
  logs_s3_access_key        = var.logs_s3_access_key
  logs_s3_secret_key        = var.logs_s3_secret_key
  logs_s3_bucket            = var.logs_s3_bucket
  registry_htpasswd         = var.registry_htpasswd
  victoria_metrics_version  = var.victoria_metrics_version
  loki_version              = var.loki_version
  grafana_version           = var.grafana_version
  hcloud_ccm_version        = var.hcloud_ccm_version
  hcloud_csi_version        = var.hcloud_csi_version
  cilium_version            = var.cilium_version
  ingress_nginx_version     = var.ingress_nginx_version
  cert_manager_version      = var.cert_manager_version
  nats_version              = var.nats_version
  kubearmor_version         = var.kubearmor_version
  kyverno_version           = var.kyverno_version
  fluent_bit_version        = var.fluent_bit_version
  argocd_version            = var.argocd_version
  knative_version           = var.knative_version
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
  node_role                = "agent"
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
  k3s_token                = random_password.k3s_token.result
  load_balancer_ip         = var.api_load_balancer_ip
  tailscale_auth_agent_key = var.tailscale_auth_k3s_agent_key
  hcloud_token             = var.hcloud_token
  hcloud_network_name      = hcloud_network.main.name
  letsencrypt_email        = var.letsencrypt_email
  depends_on               = [time_sleep.wait_for_init_node, module.control_plane_join]
}

resource "hcloud_load_balancer_target" "ingress_targets" {
  count            = local.env.worker_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress.id
  server_id        = module.worker_agents[count.index].id
  use_private_ip   = true
}

# --- THE HARD SHELL FIREWALL ---
resource "hcloud_firewall" "k3s_hard_shell" {
  name = "${local.prefix}-hard-shell-fw"

  # 1. ALLOW: Inbound from Load Balancer (API Health Checks)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = [var.api_load_balancer_ip]
  }

  # 2. ALLOW: WireGuard (Tailscale Mesh VPN)
  # This is the ONLY way you can SSH into the box.
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # 3. ALLOW: Internal Cluster Traffic (The "Private Network" still exists)
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

  # BLOCK: EVERYTHING ELSE
  # No SSH (22). No HTTP (80). No HTTPS (443).
  # The Load Balancer hits the nodes on the Private IP (10.0.x.x), not the Public IP.

  apply_to { label_selector = "cluster=${local.prefix}" }
}

output "api_endpoint" {
  value = var.api_load_balancer_ip
}

output "public_ingress_ip" {
  value = hcloud_load_balancer.ingress.ipv4
}

output "control_plane_ids" {
  value = concat([module.control_plane_init.id], module.control_plane_join[*].id)
}

output "worker_ids" {
  value = module.worker_agents[*].id
}
