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

variable "network_gateway" { default = "10.0.0.1" }

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

variable "kubearmor_version" {
  type    = string
  default = ""
}

variable "fluent_bit_version" {
  type    = string
  default = ""
}

locals {
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.load_balancer_ip}:6443"

  manifest_files = {
    "01-hcloud-secret.yaml" = templatefile("${path.module}/manifests/01-hcloud-secret.yaml", { HcloudToken = var.hcloud_token, HcloudNetwork = var.hcloud_network_name })
    "02-hcloud-ccm.yaml"    = templatefile("${path.module}/manifests/02-hcloud-ccm.yaml", { HcloudCCMVersion = var.hcloud_ccm_version, HcloudNetwork = var.hcloud_network_name })
    "03-hcloud-csi.yaml"    = templatefile("${path.module}/manifests/03-hcloud-csi.yaml", { HcloudCSIVersion = var.hcloud_csi_version })
    "04-cilium.yaml"        = templatefile("${path.module}/manifests/04-cilium.yaml", { CiliumVersion = var.cilium_version, K8sServiceHost = var.load_balancer_ip })
    "05-ingress-nginx.yaml" = templatefile("${path.module}/manifests/05-ingress-nginx.yaml", { IngressNginxVersion = var.ingress_nginx_version })
    "06-nats.yaml"          = templatefile("${path.module}/manifests/06-nats.yaml", { NatsVersion = var.nats_version })
    "07-cert-manager.yaml"  = templatefile("${path.module}/manifests/07-cert-manager.yaml", { CertManagerVersion = var.cert_manager_version })
    "08-letsencrypt-issuer.yaml" = templatefile("${path.module}/manifests/08-letsencrypt-issuer.yaml", {
      LetsEncryptEmail = var.letsencrypt_email,
      CloudEnv         = var.cloud_env
    })
    "09-gvisor-runtimeclass.yaml" = file("${path.module}/manifests/09-gvisor-runtimeclass.yaml")
    "10-internal-registry.yaml" = templatefile("${path.module}/manifests/10-internal-registry.yaml", {
      RegistryS3Bucket    = var.registry_s3_bucket
      RegistryS3AccessKey = var.registry_s3_access_key
      RegistryS3SecretKey = var.registry_s3_secret_key
      RegistryHtpasswd    = var.registry_htpasswd
    })
    "11-cilium-deny-metadata.yaml" = file("${path.module}/manifests/11-cilium-deny-metadata.yaml")
    "12-kubearmor.yaml" = templatefile("${path.module}/manifests/12-kubearmor.yaml", {
      KubearmorVersion = var.kubearmor_version
      LogsBucket       = var.logs_s3_bucket
    })
    "13-fluent-bit.yaml" = templatefile("${path.module}/manifests/13-fluent-bit.yaml", {
      FluentBitVersion = var.fluent_bit_version
      LogsBucket       = var.logs_s3_bucket
      LogsAccessKey    = var.logs_s3_access_key
      LogsSecretKey    = var.logs_s3_secret_key
    })
    "14-victoria-metrics.yaml" = templatefile("${path.module}/manifests/14-victoria-metrics.yaml", { VictoriaMetricsVersion = var.victoria_metrics_version })
    "15-loki.yaml"             = templatefile("${path.module}/manifests/15-loki.yaml", { LokiVersion = var.loki_version })
    "16-grafana.yaml"          = templatefile("${path.module}/manifests/16-grafana.yaml", { GrafanaVersion = var.grafana_version })
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
      cloud_env                 = var.cloud_env
      k3s_token                 = var.k3s_token
      k3s_init                  = var.k3s_init
      load_balancer_ip          = var.load_balancer_ip
      k3s_cluster_setting       = local.k3s_cluster_setting
      etcd_s3_access_key        = var.etcd_s3_access_key
      etcd_s3_secret_key        = var.etcd_s3_secret_key
      etcd_s3_bucket            = var.etcd_s3_bucket
      tailscale_auth_server_key = var.tailscale_auth_server_key
      network_gateway           = var.network_gateway
      manifest_injector_script  = local.manifest_injector_script
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
