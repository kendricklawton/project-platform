terraform {
  required_version = ">= 1.5.0"
}

# VARIABLES
variable "hostname" { type = string }
variable "cloud_env" { type = string }
variable "node_role" {
  type        = string
  description = "Must be 'server' or 'agent'"
}
variable "k3s_load_balancer_ip" {
  type        = string
  description = "The VIP (Virtual IP) of the API Load Balancer. For Hetzner, this is the private LB IP. For DO, this is the Private IP of the LB."
}
variable "k3s_public_lb_ip" {
  type        = string
  description = "The Public IP of the API Load Balancer (for TLS SAN)"
  default     = ""
}
variable "cloud_provider" {
  type        = string
  description = "Cloud provider name for metadata logic (e.g., 'hetzner', 'digitalocean')"
}
variable "k3s_token" {
  type      = string
  sensitive = true
}
variable "k3s_init" {
  type        = bool
  description = "If true, initializes a new cluster (only for the first server node)"
  default     = false
}
variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "The Tailscale Auth Key (Server or Agent specific)"
}
variable "etcd_s3_access_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "etcd_s3_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}
variable "etcd_s3_bucket" {
  type    = string
  default = ""
}
variable "etcd_s3_region" {
  type    = string
  default = ""
}
variable "etcd_s3_endpoint" {
  type    = string
  default = ""
}
variable "network_gateway" {
  type        = string
  description = "The gateway IP for Hetzner networking"
  default     = ""
}

# MANIFEST INJECTION
variable "manifests" {
  description = "Map of 'filename' => 'content' to inject into /var/lib/rancher/k3s/server/manifests"
  type        = map(string)
  default     = {}
}

locals {
  # Logic to determine the K3s startup flag
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.k3s_load_balancer_ip}:6443"

  # Generator script for the manifests
  manifest_injector_script = join("\n", [
    for filename, content in var.manifests :
    "echo '${base64encode(content)}' | base64 -d > /var/lib/rancher/k3s/server/manifests/${filename}"
  ])

  # Select the correct template based on role
  template_file = var.node_role == "server" ? "${path.module}/templates/cloud-init-server.yaml" : "${path.module}/templates/cloud-init-agent.yaml"
}

# OUTPUT GENERATOR
output "user_data" {
  description = "The rendered cloud-init user_data string"
  value = templatefile(local.template_file, {
    hostname        = var.hostname
    cloud_env       = var.cloud_env
    network_gateway = var.network_gateway

    # Network Abstraction
    cloud_provider = var.cloud_provider

    # K3s Config
    k3s_load_balancer_ip = var.k3s_load_balancer_ip
    k3s_public_lb_ip     = var.k3s_public_lb_ip
    k3s_token            = var.k3s_token
    k3s_init             = var.k3s_init
    k3s_cluster_setting  = local.k3s_cluster_setting
    k3s_url              = "${var.k3s_load_balancer_ip}:6443"

    # Manifests
    manifest_injector_script = local.manifest_injector_script

    # Backups
    etcd_s3_access_key = var.etcd_s3_access_key
    etcd_s3_secret_key = var.etcd_s3_secret_key
    etcd_s3_bucket     = var.etcd_s3_bucket
    etcd_s3_region     = var.etcd_s3_region
    etcd_s3_endpoint   = var.etcd_s3_endpoint

    # Auth
    tailscale_auth_key = var.tailscale_auth_key
  })
}
