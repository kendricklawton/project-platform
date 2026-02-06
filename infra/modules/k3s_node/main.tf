terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

variable "hostname" { type = string }
variable "cloud_env" { type = string }
variable "location" { type = string }
variable "ssh_key_ids" { type = list(string) }
variable "network_id" { type = string }
variable "project_name" { type = string }
variable "node_role" { type = string }
variable "k3s_token" { type = string }
variable "load_balancer_ip" { type = string }
variable "private_ip" {
  type    = string
  default = ""
}
variable "image" { type = string }
variable "server_type" { type = string }

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

# We are using the Public IP gateway (DHCP).

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "hcloud_network_name" { type = string }

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

variable "logs_s3_access_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "logs_s3_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "logs_s3_bucket" {
  type    = string
  default = ""
}

variable "registry_s3_access_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "registry_s3_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "registry_s3_bucket" {
  type    = string
  default = ""
}

variable "registry_htpasswd" {
  type      = string
  sensitive = true
  default   = ""
}

variable "letsencrypt_email" {
  type    = string
  default = ""
}

variable "loki_version" {
  type    = string
  default = ""
}

variable "grafana_version" {
  type    = string
  default = ""
}

variable "victoria_metrics_version" {
  type    = string
  default = ""
}

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

variable "kyverno_version" {
  type    = string
  default = ""
}

variable "kubearmor_version" {
  type    = string
  default = ""
}

variable "fluent_bit_version" {
  type    = string
  default = ""
}

variable "argocd_version" {
  type    = string
  default = ""
}

variable "knative_version" {
  type    = string
  default = ""
}

locals {
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.load_balancer_ip}:6443"

  manifest_files = {
    # Core
    "000-hcloud-secret.yaml" = templatefile("${path.module}/manifests/00-core/000-hcloud-secret.yaml", {
      HcloudToken   = var.hcloud_token,
      HcloudNetwork = var.hcloud_network_name
    })
    "001-hcloud-ccm.yaml" = templatefile("${path.module}/manifests/00-core/001-hcloud-ccm.yaml", {
      HcloudCCMVersion = var.hcloud_ccm_version,
      HcloudNetwork    = var.hcloud_network_name
    })
    "002-hcloud-csi.yaml" = templatefile("${path.module}/manifests/00-core/002-hcloud-csi.yaml", {
      HcloudCSIVersion = var.hcloud_csi_version
    })
    "003-gvisor-runtime.yaml" = templatefile("${path.module}/manifests/00-core/003-gvisor-runtime.yaml", {
      CiliumVersion  = var.cilium_version,
      K8sServiceHost = var.load_balancer_ip
    })
    "100-cilium.yaml" = templatefile("${path.module}/manifests/01-network/100-cilium.yaml", {
      CiliumVersion  = var.cilium_version,
      K8sServiceHost = var.load_balancer_ip
    })
    "101-ingress-nginx.yaml" = templatefile("${path.module}/manifests/01-network/101-ingress-nginx.yaml", {
      IngressNginxVersion = var.ingress_nginx_version
    })
    "102-cert-manager.yaml" = templatefile("${path.module}/manifests/01-network/102-cert-manager.yaml", {
      CertManagerVersion = var.cert_manager_version
    })
    "103-letsencrypt-issuer.yaml" = templatefile("${path.module}/manifests/01-network/103-letsencrypt-issuer.yaml", {
      LetsEncryptEmail = var.letsencrypt_email,
      CloudEnv         = var.cloud_env
    })

    # Security
    "200-kubearmor.yaml" = templatefile("${path.module}/manifests/02-security/200-kubearmor.yaml", {
      KubearmorVersion = var.kubearmor_version,
      LogsBucket       = var.logs_s3_bucket
    })
    "201-kyverno.yaml" = templatefile("${path.module}/manifests/02-security/201-kyverno.yaml", {
      KyvernoVersion = var.kyverno_version
    })
    "210-policy-enforce-gvisor.yaml"        = file("${path.module}/manifests/02-security/210-policy-enforce-gvisor.yaml")
    "211-policy-default-deny-tenants.yaml"  = file("${path.module}/manifests/02-security/211-policy-default-deny-tenants.yaml")
    "212-policy-deny-metadata-access.yaml"  = file("${path.module}/manifests/02-security/212-policy-deny-metadata-access.yaml")
    "213-policy-deny-internode-access.yaml" = file("${path.module}/manifests/02-security/213-policy-deny-internode-access.yaml")
    "214-policy-generate-quotas.yaml"       = file("${path.module}/manifests/02-security/214-policy-generate-quotas.yaml")

    # Middleware
    "300-nats.yaml" = templatefile("${path.module}/manifests/03-middleware/300-nats.yaml", {
      NatsVersion = var.nats_version
    })
    "320-knative-serving.yaml" = templatefile("${path.module}/manifests/03-middleware/320-knative-serving.yaml", {
      KnativeVersion = var.knative_version
    })
    "321-kourier.yaml" = templatefile("${path.module}/manifests/03-middleware/321-kourier.yaml", {
      KnativeVersion = var.knative_version
    })
    "322-knative-eventing.yaml" = templatefile("${path.module}/manifests/03-middleware/322-knative-eventing.yaml", {
      KnativeVersion = var.knative_version
    })
    "323-knative-nats.yaml" = templatefile("${path.module}/manifests/03-middleware/323-knative-nats.yaml", {
      KnativeVersion = var.knative_version
    })

    # Observability
    "400-fluent-bit-secret.yaml" = templatefile("${path.module}/manifests/04-observability/400-fluent-bit-secret.yaml", {
      LogsBucket    = var.logs_s3_bucket
      LogsAccessKey = var.logs_s3_access_key
      LogsSecretKey = var.logs_s3_secret_key
    })
    "401-fluent-bit.yaml" = templatefile("${path.module}/manifests/04-observability/401-fluent-bit.yaml", {
      FluentBitVersion = var.fluent_bit_version
      LogsBucket       = var.logs_s3_bucket
      LogsAccessKey    = var.logs_s3_access_key
      LogsSecretKey    = var.logs_s3_secret_key
    })
    "402-victoria-metrics.yaml" = templatefile("${path.module}/manifests/04-observability/402-victoria-metrics.yaml", {
      VictoriaMetricsVersion = var.victoria_metrics_version
    })
    "403-loki.yaml" = templatefile("${path.module}/manifests/04-observability/403-loki.yaml", {
      LokiVersion = var.loki_version
    })
    "404-grafana.yaml" = templatefile("${path.module}/manifests/04-observability/404-grafana.yaml", {
      GrafanaVersion = var.grafana_version
    })

    # Apps
    "500-registry.yaml" = templatefile("${path.module}/manifests/05-apps/500-registry.yaml", {
      RegistryS3Bucket    = var.registry_s3_bucket
      RegistryS3AccessKey = var.registry_s3_access_key
      RegistryS3SecretKey = var.registry_s3_secret_key
      RegistryHtpasswd    = var.registry_htpasswd
      CloudEnv            = var.cloud_env
      RegistryHost        = "registry.${var.cloud_env}.${var.project_name}.com"
    })
    "501-argocd.yaml" = templatefile("${path.module}/manifests/05-apps/501-argocd.yaml", {
      ArgoVersion = var.argocd_version
      CloudEnv    = var.cloud_env
      ArgoHost    = "argocd.${var.cloud_env}.${var.project_name}.com"
    })
  }

  manifest_injector_script = join("\n", [
    for filename, content in local.manifest_files :
    "echo '${base64encode(content)}' | base64 -d > /var/lib/rancher/k3s/server/manifests/${filename}"
  ])
}

resource "hcloud_server" "node" {
  name        = var.hostname
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = var.ssh_key_ids

  # This allows the node to reach the internet without a NAT gateway.
  # The Cloud Firewall (defined in main.tf) will protect it.
  public_net {
    ipv4_enabled = true
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
      cloud_env                 = var.cloud_env
      k3s_token                 = var.k3s_token
      k3s_init                  = var.k3s_init
      load_balancer_ip          = var.load_balancer_ip
      k3s_cluster_setting       = local.k3s_cluster_setting
      etcd_s3_access_key        = var.etcd_s3_access_key
      etcd_s3_secret_key        = var.etcd_s3_secret_key
      etcd_s3_bucket            = var.etcd_s3_bucket
      tailscale_auth_server_key = var.tailscale_auth_server_key
      manifest_injector_script  = local.manifest_injector_script
    }) :
    templatefile("${path.module}/templates/cloud-init-agent.yaml", {
      hostname                 = var.hostname
      cloud_env                = var.cloud_env
      k3s_url                  = "${var.load_balancer_ip}:6443"
      k3s_token                = var.k3s_token
      tailscale_auth_agent_key = var.tailscale_auth_agent_key
    })
  )
}

output "id" {
  value = hcloud_server.node.id
}

output "ipv4_address" {
  value = hcloud_server.node.ipv4_address
}
