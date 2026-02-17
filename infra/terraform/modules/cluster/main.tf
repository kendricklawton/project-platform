terraform {
  required_version = ">= 1.5.0"
}

# Context
variable "cloud_provider" {
  description = "Target Cloud: 'hetzner' or 'digitalocean'"
  type        = string
}

variable "cloud_env" {
  type = string
}

variable "project_name" {
  type = string
}

variable "k3s_api_ip" {
  description = "Internal IP/Host for the K3s API"
  type        = string
}

variable "k3s_network" {
  description = "K3s Network (Required for Hetzner CCM)"
  type        = string
  default     = ""
}

# Auth
variable "token" {
  type      = string
  sensitive = true
}

variable "letsencrypt_email" {
  type = string
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

variable "registry_s3_bucket" {
  type = string
}

variable "registry_s3_access_key" {
  type      = string
  sensitive = true
}

variable "registry_s3_secret_key" {
  type      = string
  sensitive = true
}

variable "database_s3_bucket" {
  type = string
}

variable "database_s3_access_key" {
  type      = string
  sensitive = true
}

variable "database_s3_secret_key" {
  sensitive = true
  type      = string
}

variable "logs_s3_bucket" {
  type      = string
  sensitive = true
}

variable "logs_s3_access_key" {
  type      = string
  sensitive = true
}

variable "logs_s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type = string
}

variable "s3_endpoint" {
  type = string
}

variable "registry_htpasswd" {
  type      = string
  sensitive = true
}

# Versions
variable "ccm_version" {
  type = string
}
variable "csi_version" {
  type = string
}

variable "cilium_version" {
  type = string
}

variable "ingress_nginx_version" {
  type = string
}

variable "cert_manager_version" {
  type = string
}

variable "argocd_version" {
  type = string
}

# Logic Engine
locals {
  # Path to your existing YAML files
  manifests_path = "${path.module}/manifests"

  # A. CLOUD SPECIFIC MANIFESTS

  # Hetzner Only
  hetzner_manifests = var.cloud_provider == "hetzner" ? {
    "001-hcloud-secret.yaml" = templatefile("${local.manifests_path}/010-hcloud-secret.yaml", {
      Token      = var.token
      K3sNetwork = var.k3s_network
    })
    "002-hcloud-ccm.yaml" = templatefile("${local.manifests_path}/011-hcloud-ccm.yaml", {
      CCMVersion = var.ccm_version
    })
    "003-hcloud-csi.yaml" = templatefile("${local.manifests_path}/012-hcloud-csi.yaml", {
      CSIVersion = var.csi_version
    })
  } : {}

  # DigitalOcean Only
  do_manifests = var.cloud_provider == "digitalocean" ? {
    "001-docloud-secret.yaml" = templatefile("${local.manifests_path}/020-docloud-secret.yaml", {
      Token = var.token
    })
    "002-docloud-ccm.yaml" = templatefile("${local.manifests_path}/021-docloud-ccm.yaml", {
      CCMVersion = var.ccm_version
    })
    "003-docloud-csi.yaml" = templatefile("${local.manifests_path}/022-docloud-csi.yaml", {
      CSIVersion = var.csi_version
    })
  } : {}

  # Shared Manifests
  common_manifests = {
    # Namespaces
    "000-terraform-namespaces.yaml" = templatefile("${local.manifests_path}/000-terraform-namespaces.yaml", {
      ProjectNamespace = var.project_name
    })

    # Runtime
    "100-gvisor-runtime.yaml" = file("${local.manifests_path}/100-gvisor-runtime.yaml")

    # Networking (Cilium needs the API IP injected)
    "110-cilium.yaml" = templatefile("${local.manifests_path}/110-cilium.yaml", {
      CiliumVersion  = var.cilium_version
      K8sServiceHost = var.k3s_api_ip
    })

    "120-ingress-nginx.yaml" = templatefile("${local.manifests_path}/120-ingress-nginx.yaml", {
      IngressNginxVersion = var.ingress_nginx_version
    })
    # "130-cert-manager.yaml" = templatefile("${local.manifests_path}/130-cert-manager.yaml", {
    #   CertManagerVersion = var.cert_manager_version
    # })
    # "140-letsencrypt-issuer.yaml" = templatefile("${local.manifests_path}/140-letsencrypt-issuer.yaml", {
    #   LetsEncryptEmail = var.letsencrypt_email
    #   CloudEnv         = var.cloud_env
    # })
    # "150-argocd.yaml" = file("${local.manifests_path}/150-argocd.yaml")
    # "151-root-app.yaml" = templatefile("${local.manifests_path}/151-root-app.yaml", {
    #   ArgoVersion   = var.argocd_version
    #   CloudProvider = var.cloud_provider
    #   CloudEnv      = var.cloud_env
    #   ArgoHost      = "argocd.${var.cloud_env}.${var.project_name}.com"
    # })
  }
}

# Output
output "manifests" {
  description = "The merged map of filenames to content"
  value = merge(
    local.common_manifests,
    local.hetzner_manifests,
    local.do_manifests
  )
}
