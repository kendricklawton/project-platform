terraform {
  required_version = ">= 1.5.0"
  backend "gcs" {}
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.6.0"
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

# New Variable to dynamically control your VPC without hardcoding inside locals
variable "vpc_cidr" {
  description = "The Base CIDR block for the entire Hetzner VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "master_type" { type = string }
variable "worker_type" { type = string }
variable "load_balancer_type" { type = string }

variable "location" { type = string }
variable "project_name" { type = string }
variable "cloud_env" { type = string }

variable "ssh_key_name" { type = string }
variable "talos_image_name" {
  type    = string
  default = "talos-hcloud"
}

# MODULE VARIABLES
variable "github_repo_url" { type = string }

variable "etcd_s3_bucket" { type = string }
variable "etcd_s3_access_key" {
  type      = string
  sensitive = true
}
variable "etcd_s3_secret_key" {
  type      = string
  sensitive = true
}
variable "etcd_s3_endpoint" { type = string }
variable "etcd_s3_region" { type = string }

variable "ccm_version" { type = string }
variable "csi_version" { type = string }
variable "cilium_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "argocd_version" { type = string }

variable "tailscale_oauth_client_id" { type = string }
variable "tailscale_oauth_client_secret" {
  type      = string
  sensitive = true
}
variable "tailscale_auth_nat_key" {
  type      = string
  sensitive = true
}

# PROVIDERS
provider "hcloud" {
  token = var.token
}

provider "talos" {}

# LOCALS
locals {
  prefix = "${var.location}-${var.cloud_env}"

  # Automatically calculate the subnet block without hardcoding
  nodes_cidr = cidrsubnet(var.vpc_cidr, 8, 1) # Results in 10.10.1.0/24

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

# TALOS PKI & SECRETS
resource "talos_machine_secrets" "cluster" {}

data "talos_client_configuration" "cluster" {
  cluster_name         = local.prefix
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [hcloud_load_balancer_network.k8s_api_net.ip]
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.prefix
  cluster_endpoint = "https://${hcloud_load_balancer_network.k8s_api_net.ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = { name = "none" }
        }
        externalCloudProvider = {
          enabled   = true
          manifests = []
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = local.prefix
  cluster_endpoint = "https://${hcloud_load_balancer_network.k8s_api_net.ip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      cluster = {
        externalCloudProvider = {
          enabled   = true
          manifests = []
        }
      }
    })
  ]
}

# DATA SOURCES
data "hcloud_image" "talos" {
  with_selector = "role=talos-base,location=${var.location}"
  most_recent   = true
}

data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

# NETWORK
resource "hcloud_network" "k8s_main" {
  name     = "${local.prefix}-vnet"
  ip_range = var.vpc_cidr
}

resource "hcloud_network_subnet" "k8s_nodes" {
  network_id   = hcloud_network.k8s_main.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = local.nodes_cidr
}

# NAT GATEWAY
resource "hcloud_server" "nat" {
  name        = "${local.prefix}-nat"
  image       = data.hcloud_image.nat.id # Your pre-built Packer image!
  server_type = "cpx11"
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.admin.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.k8s_main.id
  }

  depends_on = [hcloud_network_subnet.k8s_nodes]

  labels = {
    cluster = local.prefix
    role    = "nat"
  }

  # We use a simple bash script instead of a massive cloud-init YAML
  # because Packer already handled the software installations.
  user_data = <<-EOF
    #!/bin/bash
    set -e

    echo "--- Applying VPC NAT Routing ---"
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -o eth0 -j MASQUERADE
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

resource "hcloud_network_route" "egress" {
  network_id  = hcloud_network.k8s_main.id
  destination = "0.0.0.0/0"
  gateway     = tolist(hcloud_server.nat.network)[0].ip # Fetch the dynamically assigned NAT IP
  depends_on  = [hcloud_server.nat]
}

# LOAD BALANCERS
resource "hcloud_load_balancer" "k8s_api" {
  name               = "${local.prefix}-lb-api"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "k8s_api_net" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  network_id       = hcloud_network.k8s_main.id
  # IP is dynamically assigned by Hetzner DHCP
  depends_on = [hcloud_network_subnet.k8s_nodes]
}

resource "hcloud_load_balancer_service" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
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

resource "hcloud_load_balancer_service" "talos_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  protocol         = "tcp"
  listen_port      = 50000
  destination_port = 50000

  health_check {
    protocol = "tcp"
    port     = 50000
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "hcloud_load_balancer" "k8s_ingress" {
  name               = "${local.prefix}-lb-ingress"
  load_balancer_type = var.load_balancer_type
  location           = var.location
}

resource "hcloud_load_balancer_network" "k8s_ingress_net" {
  load_balancer_id = hcloud_load_balancer.k8s_ingress.id
  network_id       = hcloud_network.k8s_main.id
  # IP is dynamically assigned by Hetzner DHCP
  depends_on = [hcloud_network_subnet.k8s_nodes]
}

resource "hcloud_load_balancer_service" "k8s_http" {
  load_balancer_id = hcloud_load_balancer.k8s_ingress.id
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

resource "hcloud_load_balancer_service" "k8s_https" {
  load_balancer_id = hcloud_load_balancer.k8s_ingress.id
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

# COMPUTE: CONTROL PLANE
resource "hcloud_server" "cp_init" {
  name        = format("${local.prefix}-sv-%02d", 1)
  image       = data.hcloud_image.talos.id
  server_type = var.master_type
  location    = var.location

  user_data = data.talos_machine_configuration.controlplane.machine_config

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.k8s_main.id
    # IP is dynamically assigned by Hetzner DHCP
  }

  depends_on = [
    hcloud_network_subnet.k8s_nodes,
    hcloud_network_route.egress
  ]

  labels = {
    cluster = local.prefix
    role    = "server"
  }
}

resource "hcloud_server" "cp_join" {
  count       = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  name        = format("${local.prefix}-sv-%02d", count.index + 2)
  image       = data.hcloud_image.talos.id
  server_type = var.master_type
  location    = var.location

  user_data = data.talos_machine_configuration.controlplane.machine_config

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network { network_id = hcloud_network.k8s_main.id }

  depends_on = [hcloud_network_route.egress]

  labels = {
    cluster = local.prefix
    role    = "server"
  }
}

resource "hcloud_load_balancer_target" "k8s_api_target_init" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  server_id        = hcloud_server.cp_init.id
  use_private_ip   = true
}

resource "hcloud_load_balancer_target" "k8s_api_targets_join" {
  count            = local.env.master_count > 1 ? local.env.master_count - 1 : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  server_id        = hcloud_server.cp_join[count.index].id
  use_private_ip   = true
}

# TALOS CLUSTER BOOTSTRAP & KUBECONFIG EXPORT
resource "talos_machine_bootstrap" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  # Fetch the dynamically assigned private IP for bootstrap (fixes private network routing)
  node     = tolist(hcloud_server.cp_init.network)[0].ip
  endpoint = hcloud_load_balancer_network.k8s_api_net.ip

  depends_on = [
    hcloud_server.cp_init,
    hcloud_load_balancer_target.k8s_api_target_init
  ]
}

resource "talos_cluster_kubeconfig" "cluster" {
  depends_on           = [talos_machine_bootstrap.cluster]
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = tolist(hcloud_server.cp_init.network)[0].ip
}

# COMPUTE: WORKERS
resource "hcloud_server" "worker" {
  count       = local.env.worker_count
  name        = format("${local.prefix}-ag-%02d", count.index + 1)
  image       = data.hcloud_image.talos.id
  server_type = var.worker_type
  location    = var.location

  user_data = data.talos_machine_configuration.worker.machine_config

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network { network_id = hcloud_network.k8s_main.id }

  depends_on = [hcloud_network_route.egress]

  labels = {
    cluster = local.prefix
    role    = "agent"
  }
}

resource "hcloud_load_balancer_target" "k8s_ingress_targets" {
  count            = local.env.worker_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_ingress.id
  server_id        = hcloud_server.worker[count.index].id
  use_private_ip   = true
}

# CORE CLUSTER WORKLOADS (The Module Call)
module "core_infrastructure" {
  source = "../../module"

  cloud_provider = var.cloud_provider
  cloud_env      = var.cloud_env
  project_name   = var.project_name
  k8s_api_ip     = tolist(hcloud_server.cp_init.network)[0].ip
  k8s_network    = hcloud_network.k8s_main.name
  token          = var.token

  # Dynamic Network Variables for Cilium
  vpc_cidr              = var.vpc_cidr
  cilium_mtu            = 1450
  cilium_routing_device = "eth0"

  # Storage, Backups & GitOps
  github_repo_url    = var.github_repo_url
  etcd_s3_bucket     = var.etcd_s3_bucket
  etcd_s3_access_key = var.etcd_s3_access_key
  etcd_s3_secret_key = var.etcd_s3_secret_key
  etcd_s3_endpoint   = var.etcd_s3_endpoint
  etcd_s3_region     = var.etcd_s3_region

  tailscale_oauth_client_id     = var.tailscale_oauth_client_id
  tailscale_oauth_client_secret = var.tailscale_oauth_client_secret

  # Inject the Talosconfig generated by Terraform for backups
  talosconfig = data.talos_client_configuration.cluster.talos_config

  ccm_version           = var.ccm_version
  csi_version           = var.csi_version
  cilium_version        = var.cilium_version
  ingress_nginx_version = var.ingress_nginx_version
  argocd_version        = var.argocd_version

  depends_on = [talos_cluster_kubeconfig.cluster]
}

# FIREWALL
resource "hcloud_firewall" "cluster_fw" {
  name = "${local.prefix}-fw-${var.location}"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["${hcloud_load_balancer_network.k8s_api_net.ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "${hcloud_load_balancer_network.k8s_ingress_net.ip}/32",
      var.vpc_cidr
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "${hcloud_load_balancer_network.k8s_ingress_net.ip}/32",
      var.vpc_cidr
    ]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

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

# OUTPUTS
output "k8s_api_endpoint" {
  value = hcloud_load_balancer_network.k8s_api_net.ip
}

output "talosconfig" {
  description = "The raw talosconfig for managing the nodes via talosctl"
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "The standard kubeconfig generated by Talos for kubectl"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "nat_public_ip" {
  description = "The public IP of the NAT server (useful for SSH)"
  value       = hcloud_server.nat.ipv4_address
}
