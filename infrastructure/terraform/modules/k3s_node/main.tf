# --- CORE PLATFORM VARIABLES ---
variable "cloud_provider_name" {
  description = "The identifier for the cloud provider (e.g., 'hcloud', 'docloud')"
  type        = string
}

variable "cloud_provider_mtu" {
  type = number
}

variable "k3s_load_balancer_ip" {
  description = "The static IP of the K3s Control Plane Load Balancer"
  type        = string
}

variable "cilium_version" {
  type = string
}

variable "ingress_nginx_version" {
  type = string
}

variable "argocd_version" {
  type = string
}

variable "sealed_secrets_version" {
  type = string
}

variable "git_repo_url" {
  type = string
}

# --- CLOUD-SPECIFIC MANIFEST VARIABLES ---
variable "token" {
  description = "The API token for the specific cloud provider's CCM/CSI"
  type        = string
  sensitive   = true
}

variable "ccm_version" {
  type = string
}

variable "csi_version" {
  type = string
}

# Hetzner Specific Manifest Variables
variable "hcloud_network_name" {
  type    = string
  default = ""
}

locals {
  core_manifests = {
    "100-gvisor-runtimeclass.yaml" = file("${path.module}/bootstrap/100-gvisor-runtimeclass.yaml")
    "110-cilium.yaml" = templatefile("${path.module}/bootstrap/110-cilium.yaml", {
      MTU            = var.cloud_provider_mtu
      CiliumVersion  = var.cilium_version,
      K8sServiceHost = var.k3s_load_balancer_ip
    })
    "120-ingress-nginx.yaml" = templatefile("${path.module}/bootstrap/120-ingress-nginx.yaml", {
      IngressNginxVersion = var.ingress_nginx_version
    })
    "130-sealed-secrets.yaml" = templatefile("${path.module}/bootstrap/130-sealed-secrets.yaml", {
      SealedSecretsVersion = var.sealed_secrets_version
    })
    "140-agrocd.yaml" = templatefile("${path.module}/bootstrap/140-agrocd.yaml", {
      ArgoCDVersion = var.argocd_version
    })
    "150-root-app.yaml" = templatefile("${path.module}/bootstrap/150-root-app.yaml", {
      GitRepoURL = var.git_repo_url
    })
  }

  hcloud_manifests = var.cloud_provider_name == "hcloud" ? {
    "000-hcloud-secret.yaml" = templatefile("${path.module}/bootstrap/000-hcloud-secret.yaml", {
      Token   = var.token,
      Network = var.hcloud_network_name
    })
    "010-hcloud-ccm.yaml" = templatefile("${path.module}/bootstrap/010-hcloud-ccm.yaml", {
      CCMVersion = var.ccm_version
    })
    "020-hcloud-csi.yaml" = templatefile("${path.module}/bootstrap/020-hcloud-csi.yaml", {
      CSIVersion = var.csi_version
    })
  } : {}

  docloud_manifests = var.cloud_provider_name == "docloud" ? {
    "000-docloud-secret.yaml" = templatefile("${path.module}/bootstrap/000-docloud-secret.yaml", {
      Token = var.token
    })
    "010-docloud-ccm.yaml" = templatefile("${path.module}/bootstrap/010-docloud-ccm.yaml", {
      CCMVersion = var.ccm_version
    })
    "020-docloud-csi.yaml" = templatefile("${path.module}/bootstrap/020-docloud-csi.yaml", {
      CSIVersion = var.csi_version
    })
  } : {}

  all_manifests = merge(local.core_manifests, local.hcloud_manifests, local.docloud_manifests)
}

output "rendered_manifests" {
  description = "The complete, flattened set of manifests to upload to the K3s server"
  value       = local.all_manifests
}
