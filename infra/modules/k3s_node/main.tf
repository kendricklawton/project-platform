terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

variable "name" { type = string }
variable "location" { type = string }
variable "server_type" { type = string }
variable "ssh_key_ids" { type = list(string) }
variable "network_id" { type = string }
variable "project_name" { type = string }
variable "node_role" { type = string } # "server" | "agent" | "nat"
variable "k3s_token" { type = string }
variable "lb_ip" { type = string }
variable "private_ip" { type = string } # New variable for static IP

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "k3s_init" {
  type    = bool
  default = false
}

variable "nat_gateway_ip" {
  type    = string
  default = "10.0.1.2"
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

variable "tailscale_auth_nat_key" {
  type      = string
  sensitive = true
  default   = ""
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

locals {
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.lb_ip}:6443"
}

resource "hcloud_server" "node" {
  name        = var.name
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
      hostname                  = var.name
      nat_gateway_ip            = var.nat_gateway_ip
      k3s_token                 = var.k3s_token
      lb_ip                     = var.lb_ip
      k3s_cluster_setting       = local.k3s_cluster_setting
      project_name              = var.project_name
      s3_access_key             = var.s3_access_key
      s3_secret_key             = var.s3_secret_key
      s3_bucket                 = var.s3_bucket
      tailscale_auth_server_key = var.tailscale_auth_server_key
      hcloud_token              = var.hcloud_token
      hcloud_network_name       = var.hcloud_network_name
    }) :
    var.node_role == "nat" ? templatefile("${path.module}/templates/cloud-init-nat.yaml", {
      hostname               = var.name
      tailscale_auth_nat_key = var.tailscale_auth_nat_key
    }) :
    templatefile("${path.module}/templates/cloud-init-agent.yaml", {
      hostname                 = var.name
      nat_gateway_ip           = var.nat_gateway_ip
      k3s_url                  = "${var.lb_ip}:6443"
      k3s_token                = var.k3s_token
      tailscale_auth_agent_key = var.tailscale_auth_agent_key
    })
  )
}

output "id" {
  value = hcloud_server.node.id
}

output "private_ip" {
  value = hcloud_server.node.network[*].ip
}
