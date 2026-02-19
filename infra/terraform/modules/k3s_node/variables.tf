# VARIABLES
variable "hostname" { type = string }
variable "cloud_env" { type = string }
variable "node_role" {
  type        = string
  description = "Must be 'server' or 'agent'"
}

variable "k3s_api_lb_ip" {
  type = string
}
variable "k3s_ingress_lb_ip" {
  type    = string
  default = ""
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
