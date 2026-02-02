terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

# --- VARIABLES ---
variable "hostname" { type = string }
variable "cloud_env" { type = string }
variable "location" { type = string }
variable "server_type" { type = string }
variable "ssh_key_ids" { type = list(string) }
variable "network_id" { type = string }
variable "project_name" { type = string }
variable "node_role" { type = string } # "server" | "agent"
variable "k3s_token" { type = string }
variable "load_balancer_ip" { type = string }

variable "private_ip" {
  type    = string
  default = null
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "k3s_init" {
  type    = bool
  default = false
}

variable "tailscale_auth_server_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tailscale_auth_agent_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "network_gateway" {
  type    = string
  default = "10.0.0.1"
}

variable "hcloud_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "hcloud_network_name" {
  type    = string
  default = ""
}

variable "s3_access_key" {
  type    = string
  default = null
}

variable "s3_secret_key" {
  type    = string
  default = null
}

variable "s3_bucket" {
  type    = string
  default = null
}

variable "letsencrypt_email" {
  type    = string
  default = null
}

# Component Versions
variable "hcloud_ccm_version" {
  type    = string
  default = ""
}

variable "hcloud_csi_version" {
  type    = string
  default = ""
}

variable "cilium_version" {
  type    = string
  default = ""
}

variable "ingress_nginx_version" {
  type    = string
  default = ""
}

variable "cert_manager_version" {
  type    = string
  default = ""
}

variable "nats_version" {
  type    = string
  default = ""
}

locals {
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.load_balancer_ip}:6443"
}

resource "hcloud_server" "node" {
  name        = var.hostname
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = var.ssh_key_ids

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = var.network_id
    ip         = var.private_ip
  }

  labels = {
    cluster = var.project_name
    role    = var.node_role
  }

  user_data = (
    var.node_role == "server" ? templatefile("${path.module}/templates/cloud-init-server.yaml", {
      hostname                  = var.hostname
      letsencrypt_email         = var.letsencrypt_email
      cloud_env                 = var.cloud_env
      k3s_token                 = var.k3s_token
      k3s_init                  = var.k3s_init
      load_balancer_ip          = var.load_balancer_ip
      k3s_cluster_setting       = local.k3s_cluster_setting
      project_name              = var.project_name
      s3_access_key             = var.s3_access_key
      s3_secret_key             = var.s3_secret_key
      s3_bucket                 = var.s3_bucket
      tailscale_auth_server_key = var.tailscale_auth_server_key
      hcloud_token              = var.hcloud_token
      hcloud_network_name       = var.hcloud_network_name
      location                  = var.location
      hcloud_ccm_version        = var.hcloud_ccm_version
      hcloud_csi_version        = var.hcloud_csi_version
      cilium_version            = var.cilium_version
      ingress_nginx_version     = var.ingress_nginx_version
      cert_manager_version      = var.cert_manager_version
      nats_version              = var.nats_version
      network_gateway           = var.network_gateway
    }) :
    templatefile("${path.module}/templates/cloud-init-agent.yaml", {
      hostname                 = var.hostname
      cloud_env                = var.cloud_env
      k3s_url                  = "${var.load_balancer_ip}:6443"
      k3s_token                = var.k3s_token
      tailscale_auth_agent_key = var.tailscale_auth_agent_key
      network_gateway          = var.network_gateway
    })
  )
}

output "id" {
  value = hcloud_server.node.id
}

output "ipv4_address" {
  value = hcloud_server.node.ipv4_address
}
