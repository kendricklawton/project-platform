terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25.0"
    }
  }
}

# VARIABLES
variable "cloud_provider" {
  description = "Target Cloud: 'hetzner' or 'digitalocean'"
  type        = string
}

variable "token" {
  type      = string
  sensitive = true
}

variable "cloud_env" {
  type = string
}

variable "project_name" {
  type = string
}

variable "k8s_api_ip" {
  description = "Internal IP/Host for the Kubernetes API"
  type        = string
}

variable "k8s_network" {
  description = "VPC Network ID (Required for Hetzner CCM)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "The CIDR block of the VPC (e.g., 10.10.0.0/16) for Hetzner Cloud, (e.g., 10.20.0.0/16) for DigitalOcean"
  type        = string
}

variable "cilium_mtu" {
  description = "The Maximum Transmission Unit for the cloud provider's VPC"
  type        = number
}

variable "cilium_routing_device" {
  description = "The network interface handling VPC traffic (usually eth0 or eth1)"
  type        = string
  default     = "eth0"
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

variable "etcd_s3_endpoint" {
  type = string
}

variable "etcd_s3_region" {
  type = string
}

variable "github_repo_url" {
  description = "The Git repository URL for Argo CD to sync from"
  type        = string
}

variable "tailscale_oauth_client_id" {
  type = string
}

variable "tailscale_oauth_client_secret" {
  type      = string
  sensitive = true
}

variable "talosconfig" {
  description = "The raw talosconfig string so the backup pod can authenticate with the Talos API"
  type        = string
  sensitive   = true
}

# Versions
variable "ccm_version" { type = string }
variable "csi_version" { type = string }
variable "cilium_version" { type = string }
variable "ingress_nginx_version" { type = string }
variable "argocd_version" { type = string }

# LOCALS
locals {
  manifests_path = "${path.module}/manifests"
}

# SECRETS (Cloud Provider API Tokens)
resource "kubernetes_secret" "hcloud" {
  count = var.cloud_provider == "hetzner" ? 1 : 0
  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }
  data = {
    token   = var.token
    network = var.k8s_network
  }
}

resource "kubernetes_secret" "digitalocean" {
  count = var.cloud_provider == "digitalocean" ? 1 : 0
  metadata {
    name      = "digitalocean"
    namespace = "kube-system"
  }
  data = {
    "access-token" = var.token
  }
}

# SECRETS (For Backups & Talos API Access)
resource "kubernetes_secret" "talosconfig" {
  metadata {
    name      = "talos-admin-config"
    namespace = "kube-system"
  }
  data = {
    "talosconfig" = var.talosconfig
  }
}

resource "kubernetes_secret" "etcd_backup_s3" {
  metadata {
    name      = "etcd-backup-s3"
    namespace = "kube-system"
  }
  data = {
    "access-key" = var.etcd_s3_access_key
    "secret-key" = var.etcd_s3_secret_key
  }
}

# CLOUD CONTROLLER MANAGERS (CCM)
resource "helm_release" "hcloud_ccm" {
  count      = var.cloud_provider == "hetzner" ? 1 : 0
  name       = "hcloud-cloud-controller-manager"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-cloud-controller-manager"
  version    = var.ccm_version
  namespace  = "kube-system"

  values = [
    templatefile("${local.manifests_path}/010-hcloud-ccm-values.yaml", {})
  ]

  depends_on = [kubernetes_secret.hcloud]
}

resource "helm_release" "digitalocean_ccm" {
  count      = var.cloud_provider == "digitalocean" ? 1 : 0
  name       = "digitalocean-cloud-controller-manager"
  repository = "https://digitalocean.github.io/digitalocean-cloud-controller-manager"
  chart      = "digitalocean-cloud-controller-manager"
  version    = var.ccm_version
  namespace  = "kube-system"

  # Uses default chart values
  depends_on = [kubernetes_secret.digitalocean]
}

# CONTAINER STORAGE INTERFACES (CSI)
resource "helm_release" "hcloud_csi" {
  count      = var.cloud_provider == "hetzner" ? 1 : 0
  name       = "hcloud-csi"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-csi"
  version    = var.csi_version
  namespace  = "kube-system"

  values = [
    templatefile("${local.manifests_path}/020-hcloud-csi-values.yaml", {})
  ]
}

resource "helm_release" "digitalocean_csi" {
  count      = var.cloud_provider == "digitalocean" ? 1 : 0
  name       = "csi-digitalocean"
  repository = "https://digitalocean.github.io/csi-digitalocean"
  chart      = "csi-digitalocean"
  version    = var.csi_version
  namespace  = "kube-system"

  # Uses default chart values
}

# RAW MANIFESTS (gVisor Runtime)
resource "kubernetes_manifest" "gvisor" {
  manifest = yamldecode(file("${local.manifests_path}/100-gvisor-runtime.yaml"))
}

# CNI (Cilium)
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  values = [
    templatefile("${local.manifests_path}/110-cilium.yaml", {
      K8sServiceHost = var.k8s_api_ip
      VpcCidr        = var.vpc_cidr
      Mtu            = var.cilium_mtu
      RoutingDevice  = var.cilium_routing_device
    })
  ]
}

# INGRESS (Nginx)
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    templatefile("${local.manifests_path}/120-ingress-nginx.yaml", {
      K8sServiceHost = var.k8s_api_ip
    })
  ]

  depends_on = [helm_release.cilium]
}

# REMOTE ACCESS (Tailscale Operator)
resource "helm_release" "tailscale" {
  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  namespace        = "tailscale"
  create_namespace = true

  values = [
    templatefile("${local.manifests_path}/130-tailscale.yaml", {
      ClientId     = var.tailscale_oauth_client_id
      ClientSecret = var.tailscale_oauth_client_secret
    })
  ]
}

# ETCD BACKUP CRONJOB
resource "kubernetes_manifest" "etcd_backup" {
  manifest = yamldecode(templatefile("${local.manifests_path}/140-etcd-backup.yaml", {
    K8sApiIp   = var.k8s_api_ip
    S3Bucket   = var.etcd_s3_bucket
    S3Endpoint = var.etcd_s3_endpoint
    S3Region   = var.etcd_s3_region
  }))

  depends_on = [
    kubernetes_secret.talosconfig,
    kubernetes_secret.etcd_backup_s3
  ]
}

# ARGOCD (Commented out until ready)
/*
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = true

  values = [
    templatefile("${local.manifests_path}/150-argocd.yaml", {
      CloudEnv    = var.cloud_env
      ArgoHost    = "argocd.${var.cloud_env}.${var.project_name}.com"
    })
  ]

  depends_on = [helm_release.ingress_nginx]
}

resource "kubernetes_manifest" "argocd_root_app" {
  manifest = yamldecode(templatefile("${local.manifests_path}/160-root-app.yaml", {
    RepoURL = var.github_repo_url
  }))

  depends_on = [helm_release.argocd]
}
*/
