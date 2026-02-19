# terraform {
#   required_version = ">= 1.5.0"
#   backend "gcs" {}
#   required_providers {
#     digitalocean = {
#       source  = "digitalocean/digitalocean"
#       version = "~> 2.34"
#     }
#     talos = {
#       source  = "siderolabs/talos"
#       version = "~> 0.6.0"
#     }
#     time = {
#       source  = "hashicorp/time"
#       version = "~> 0.9.0"
#     }
#     random = {
#       source  = "hashicorp/random"
#       version = "~> 3.5.1"
#     }
#   }
# }

# # ------------------------------------------------------------------------------
# # VARIABLES
# # ------------------------------------------------------------------------------
# variable "cloud_provider" {
#   default = "digitalocean"
#   type    = string
# }

# variable "token" {
#   description = "DigitalOcean API token"
#   type        = string
#   sensitive   = true
# }

# variable "vpc_cidr" {
#   description = "The Base CIDR block for the entire VPC"
#   type        = string
#   default     = "10.20.0.0/16"
# }

# variable "master_type" { type = string }
# variable "worker_type" { type = string }
# variable "location" { type = string }
# variable "project_name" { type = string }
# variable "cloud_env" { type = string }
# variable "ssh_key_name" { type = string }

# # MODULE VARIABLES
# variable "github_repo_url" { type = string }
# variable "etcd_s3_bucket" { type = string }
# variable "etcd_s3_access_key" {
#   type      = string
#   sensitive = true
# }

# variable "etcd_s3_secret_key" {
#   type      = string
#   sensitive = true
# }

# variable "etcd_s3_endpoint" { type = string }
# variable "etcd_s3_region" { type = string }

# # Versions
# variable "ccm_version" { type = string }
# variable "csi_version" { type = string }
# variable "cilium_version" { type = string }
# variable "ingress_nginx_version" { type = string }
# variable "argocd_version" { type = string }

# # Tailscale OAuth & NAT
# variable "tailscale_oauth_client_id" { type = string }
# variable "tailscale_oauth_client_secret" {
#   type      = string
#   sensitive = true
# }
# variable "tailscale_auth_nat_key" {
#   type      = string
#   sensitive = true
# }

# # ------------------------------------------------------------------------------
# # PROVIDERS
# # ------------------------------------------------------------------------------
# provider "digitalocean" {
#   token = var.token
# }

# provider "talos" {}

# # ------------------------------------------------------------------------------
# # LOCALS
# # ------------------------------------------------------------------------------
# locals {
#   prefix = "${var.location}-${var.cloud_env}"

#   config = {
#     dev  = { master_count = 1, worker_count = 1 }
#     prod = { master_count = 3, worker_count = 3 }
#   }
#   env = local.config[var.cloud_env]
# }

# # ------------------------------------------------------------------------------
# # TALOS PKI & SECRETS
# # ------------------------------------------------------------------------------
# resource "talos_machine_secrets" "cluster" {}

# data "talos_client_configuration" "cluster" {
#   cluster_name         = local.prefix
#   client_configuration = talos_machine_secrets.cluster.client_configuration
#   endpoints            = [digitalocean_loadbalancer.k8s_api.ip]
# }

# data "talos_machine_configuration" "controlplane" {
#   cluster_name     = local.prefix
#   cluster_endpoint = "https://${digitalocean_loadbalancer.k8s_api.ip}:6443"
#   machine_type     = "controlplane"
#   machine_secrets  = talos_machine_secrets.cluster.machine_secrets

#   config_patches = [
#     yamlencode({
#       cluster = {
#         network = {
#           cni = { name = "none" }
#         }
#         externalCloudProvider = {
#           enabled   = true
#           manifests = []
#         }
#       }
#     })
#   ]
# }

# data "talos_machine_configuration" "worker" {
#   cluster_name     = local.prefix
#   cluster_endpoint = "https://${digitalocean_loadbalancer.k8s_api.ip}:6443"
#   machine_type     = "worker"
#   machine_secrets  = talos_machine_secrets.cluster.machine_secrets

#   config_patches = [
#     yamlencode({
#       cluster = {
#         externalCloudProvider = {
#           enabled   = true
#           manifests = []
#         }
#       }
#     })
#   ]
# }

# # ------------------------------------------------------------------------------
# # DATA SOURCES
# # ------------------------------------------------------------------------------
# data "digitalocean_ssh_key" "admin" {
#   name = var.ssh_key_name
# }

# # Use your custom Packer-built NAT image
# data "digitalocean_images" "nat_base" {
#   filter {
#     key    = "name"
#     values = ["${var.location}-nat-gateway-v1"]
#   }
# }

# # ------------------------------------------------------------------------------
# # NETWORK
# # ------------------------------------------------------------------------------
# resource "digitalocean_vpc" "main" {
#   name     = "${local.prefix}-vpc"
#   region   = var.location
#   ip_range = var.vpc_cidr
# }

# # ------------------------------------------------------------------------------
# # NAT GATEWAY (Ubuntu Droplet)
# # ------------------------------------------------------------------------------
# resource "digitalocean_droplet" "nat" {
#   name     = "${local.prefix}-nat"
#   size     = "s-1vcpu-1gb"
#   image    = data.digitalocean_images.nat_base.images[0].id
#   region   = var.location
#   vpc_uuid = digitalocean_vpc.main.id
#   ssh_keys = [data.digitalocean_ssh_key.admin.id]

#   # Dynamic NAT configuration and Tailscale Join
#   user_data = <<-EOF
#     #!/bin/bash
#     set -e

#     echo "--- Applying VPC NAT Routing ---"
#     WAN_IFACE=$(ip route show default | awk '{print $5}' | head -n1)
#     iptables -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE
#     netfilter-persistent save

#     echo "--- Starting Tailscale Join Loop ---"
#     NEXT_WAIT_TIME=0
#     until tailscale up \
#       --authkey=${var.tailscale_auth_nat_key} \
#       --ssh \
#       --hostname=${local.prefix}-nat \
#       --advertise-tags="tag:nat" \
#       --advertise-routes=${var.vpc_cidr} \
#       --reset >> /var/log/tailscale-join.log 2>&1 || [ $NEXT_WAIT_TIME -eq 12 ];
#     do
#       sleep 5
#       NEXT_WAIT_TIME=$((NEXT_WAIT_TIME+1))
#     done
#   EOF
# }

# # ------------------------------------------------------------------------------
# # LOAD BALANCERS
# # ------------------------------------------------------------------------------
# resource "digitalocean_loadbalancer" "k8s_api" {
#   name     = "${local.prefix}-lb-api"
#   region   = var.location
#   vpc_uuid = digitalocean_vpc.main.id

#   forwarding_rule {
#     entry_port      = 6443
#     entry_protocol  = "tcp"
#     target_port     = 6443
#     target_protocol = "tcp"
#   }

#   forwarding_rule {
#     entry_port      = 50000
#     entry_protocol  = "tcp"
#     target_port     = 50000
#     target_protocol = "tcp"
#   }

#   healthcheck {
#     protocol = "tcp"
#     port     = 6443
#   }

#   droplet_tag = "${local.prefix}-server"
# }

# resource "digitalocean_loadbalancer" "k8s_ingress" {
#   name                  = "${local.prefix}-lb-ingress"
#   region                = var.location
#   vpc_uuid              = digitalocean_vpc.main.id
#   enable_proxy_protocol = true

#   forwarding_rule {
#     entry_port      = 80
#     entry_protocol  = "tcp"
#     target_port     = 80
#     target_protocol = "tcp"
#   }

#   forwarding_rule {
#     entry_port      = 443
#     entry_protocol  = "tcp"
#     target_port     = 443
#     target_protocol = "tcp"
#   }

#   healthcheck {
#     port     = 80
#     protocol = "tcp"
#   }

#   droplet_tag = "${local.prefix}-agent"
# }

# # ------------------------------------------------------------------------------
# # COMPUTE: CONTROL PLANE
# # ------------------------------------------------------------------------------
# resource "digitalocean_droplet" "cp_init" {
#   name      = format("${local.prefix}-sv-%02d", 1)
#   image     = "talos-digital-ocean-tutorial" # Use the name from your Image Factory setup
#   region    = var.location
#   size      = var.master_type
#   vpc_uuid  = digitalocean_vpc.main.id
#   ssh_keys  = [data.digitalocean_ssh_key.admin.id]
#   tags      = ["${local.prefix}-server"]
#   user_data = data.talos_machine_configuration.controlplane.machine_config
# }

# resource "digitalocean_droplet" "cp_join" {
#   count     = local.env.master_count > 1 ? local.env.master_count - 1 : 0
#   name      = format("${local.prefix}-sv-%02d", count.index + 2)
#   image     = "talos-digital-ocean-tutorial"
#   region    = var.location
#   size      = var.master_type
#   vpc_uuid  = digitalocean_vpc.main.id
#   ssh_keys  = [data.digitalocean_ssh_key.admin.id]
#   tags      = ["${local.prefix}-server"]
#   user_data = data.talos_machine_configuration.controlplane.machine_config
# }

# # ------------------------------------------------------------------------------
# # TALOS CLUSTER BOOTSTRAP & KUBECONFIG EXPORT
# # ------------------------------------------------------------------------------
# resource "talos_machine_bootstrap" "cluster" {
#   client_configuration = talos_machine_secrets.cluster.client_configuration
#   node                 = digitalocean_droplet.cp_init.ipv4_address_private
#   endpoint             = digitalocean_loadbalancer.k8s_api.ip

#   depends_on = [digitalocean_droplet.cp_init]
# }

# resource "talos_cluster_kubeconfig" "cluster" {
#   depends_on           = [talos_machine_bootstrap.cluster]
#   client_configuration = talos_machine_secrets.cluster.client_configuration
#   node                 = digitalocean_droplet.cp_init.ipv4_address_private
# }

# # ------------------------------------------------------------------------------
# # COMPUTE: WORKERS
# # ------------------------------------------------------------------------------
# resource "digitalocean_droplet" "worker" {
#   count     = local.env.worker_count
#   name      = format("${local.prefix}-ag-%02d", count.index + 1)
#   image     = "talos-digital-ocean-tutorial"
#   region    = var.location
#   size      = var.worker_type
#   vpc_uuid  = digitalocean_vpc.main.id
#   ssh_keys  = [data.digitalocean_ssh_key.admin.id]
#   tags      = ["${local.prefix}-agent"]
#   user_data = data.talos_machine_configuration.worker.machine_config
# }

# # ------------------------------------------------------------------------------
# # CORE CLUSTER WORKLOADS (Module Call)
# # ------------------------------------------------------------------------------
# module "core_infrastructure" {
#   source = "../../module"

#   cloud_provider = "digitalocean"
#   cloud_env      = var.cloud_env
#   project_name   = var.project_name
#   k8s_api_ip     = digitalocean_droplet.cp_init.ipv4_address_private
#   token          = var.token

#   vpc_cidr              = var.vpc_cidr
#   cilium_mtu            = 1500 # DigitalOcean standard
#   cilium_routing_device = "eth0"

#   github_repo_url    = var.github_repo_url
#   etcd_s3_bucket     = var.etcd_s3_bucket
#   etcd_s3_access_key = var.etcd_s3_access_key
#   etcd_s3_secret_key = var.etcd_s3_secret_key
#   etcd_s3_endpoint   = var.etcd_s3_endpoint
#   etcd_s3_region     = var.etcd_s3_region

#   tailscale_oauth_client_id     = var.tailscale_oauth_client_id
#   tailscale_oauth_client_secret = var.tailscale_oauth_client_secret
#   talosconfig                   = data.talos_client_configuration.cluster.talos_config

#   ccm_version           = var.ccm_version
#   csi_version           = var.csi_version
#   cilium_version        = var.cilium_version
#   ingress_nginx_version = var.ingress_nginx_version
#   argocd_version        = var.argocd_version

#   depends_on = [talos_cluster_kubeconfig.cluster]
# }

# # ------------------------------------------------------------------------------
# # FIREWALL
# # ------------------------------------------------------------------------------
# resource "digitalocean_firewall" "cluster_fw" {
#   name = "${local.prefix}-fw"
#   tags = ["${local.prefix}-server", "${local.prefix}-agent"]

#   # API Access
#   inbound_rule {
#     protocol                  = "tcp"
#     port_range                = "6443"
#     source_load_balancer_uids = [digitalocean_loadbalancer.k8s_api.id]
#   }

#   # Talos Management
#   inbound_rule {
#     protocol         = "tcp"
#     port_range       = "50000"
#     source_addresses = ["0.0.0.0/0", "::/0"]
#   }

#   # HTTP/S Access
#   inbound_rule {
#     protocol                  = "tcp"
#     port_range                = "80"
#     source_load_balancer_uids = [digitalocean_loadbalancer.k8s_ingress.id]
#   }

#   inbound_rule {
#     protocol                  = "tcp"
#     port_range                = "443"
#     source_load_balancer_uids = [digitalocean_loadbalancer.k8s_ingress.id]
#   }

#   # Internal VPC Traffic
#   inbound_rule {
#     protocol         = "tcp"
#     port_range       = "1-65535"
#     source_addresses = [var.vpc_cidr]
#   }

#   inbound_rule {
#     protocol         = "udp"
#     port_range       = "1-65535"
#     source_addresses = [var.vpc_cidr]
#   }

#   # Outbound
#   outbound_rule {
#     protocol              = "tcp"
#     port_range            = "1-65535"
#     destination_addresses = ["0.0.0.0/0", "::/0"]
#   }

#   outbound_rule {
#     protocol              = "udp"
#     port_range            = "1-65535"
#     destination_addresses = ["0.0.0.0/0", "::/0"]
#   }
# }

# # ------------------------------------------------------------------------------
# # OUTPUTS
# # ------------------------------------------------------------------------------
# output "k8s_api_endpoint" {
#   value = digitalocean_loadbalancer.k8s_api.ip
# }

# output "talosconfig" {
#   value     = data.talos_client_configuration.cluster.talos_config
#   sensitive = true
# }

# output "kubeconfig" {
#   value     = talos_cluster_kubeconfig.cluster.kubeconfig_raw
#   sensitive = true
# }

# output "nat_public_ip" {
#   value = digitalocean_droplet.nat.ipv4_address
# }
