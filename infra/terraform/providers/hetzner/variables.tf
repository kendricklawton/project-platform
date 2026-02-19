# VARIABLES
variable "cloud_provider" {
  default = "hetzner"
  type    = string
}

variable "token" {
  type      = string
  sensitive = true
}

variable "vpc_cidr" {
  description = "The Base CIDR block for the entire Hetzner VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "network_mtu" {
  description = "The Maximum Transmission Unit (MTU) for the Hetzner VPC"
  type        = number
  default     = 1450
}

variable "network_gateway" {
  description = "The internal IP of the NAT gateway (e.g. 10.10.1.2)"
  default     = "10.10.1.2"
  type        = string
}

variable "nat_type" { type = string }
variable "master_type" { type = string }
variable "worker_type" { type = string }
variable "load_balancer_type" { type = string }

variable "location" { type = string }
variable "project_name" { type = string }
variable "cloud_env" { type = string }

variable "ssh_key_name" { type = string }

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

variable "private_interface" {
  type    = string
  default = "enp7s0"
}

variable "tailscale_auth_nat_key" {
  type      = string
  sensitive = true
}

variable "tailscale_auth_k3s_server_key" {
  type      = string
  sensitive = true
}

variable "tailscale_auth_k3s_agent_key" {
  type      = string
  sensitive = true
}
