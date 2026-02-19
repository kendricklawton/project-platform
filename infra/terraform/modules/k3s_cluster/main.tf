terraform {
  required_version = ">= 1.5.0"
}

# Logic Engine
locals {
  manifests_path = "${path.module}/manifests"

  hetzner_manifests = var.cloud_provider == "hetzner" ? {
    "001-hcloud-secret.yaml" = templatefile("${local.manifests_path}/010-hcloud-secret.yaml", {
      Token   = var.token
      Network = var.network
    })
    "002-hcloud-ccm.yaml" = templatefile("${local.manifests_path}/011-hcloud-ccm.yaml", {
      CCMVersion = var.ccm_version
    })
    "003-hcloud-csi.yaml" = templatefile("${local.manifests_path}/012-hcloud-csi.yaml", {
      CSIVersion = var.csi_version
    })
  } : {}

  digitalocean_manifests = var.cloud_provider == "digitalocean" ? {
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

  core_manifests = {
    "100-gvisor-runtime.yaml" = file("${local.manifests_path}/100-gvisor-runtime.yaml")
    "110-cilium.yaml" = templatefile("${local.manifests_path}/110-cilium.yaml", {
      CiliumVersion    = var.cilium_version
      K8sServiceHost   = var.api_ip
      VpcCidr          = var.vpc_cidr
      NetworkMtu       = var.network_mtu
      OperatorReplicas = var.operator_replicas
      PrivateInterface = var.private_interface
    })
    # "120-ingress-nginx.yaml" = templatefile("${local.manifests_path}/120-ingress-nginx.yaml", {
    #   IngressNginxVersion = var.ingress_nginx_version
    # })
    # "130-argocd.yaml" = file("${local.manifests_path}/130-argocd.yaml")
    # "131-root-app.yaml" = templatefile("${local.manifests_path}/131-root-app.yaml", {
    #   ArgoVersion   = var.argocd_version
    #   CloudProvider = var.cloud_provider
    #   CloudEnv      = var.cloud_env
    #   ArgoHost      = "argocd.${var.cloud_env}.${var.project_name}.com"
    # })
  }
}

output "manifests" {
  description = "The merged map of filenames to content"
  value = merge(
    local.core_manifests,
    local.hetzner_manifests,
    local.digitalocean_manifests
  )
}
