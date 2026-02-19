output "user_data" {
  description = "The rendered cloud-init user_data string"
  value = templatefile(local.template_file, {
    hostname        = var.hostname
    cloud_env       = var.cloud_env
    network_gateway = var.network_gateway

    # Network Abstraction
    cloud_provider = var.cloud_provider

    # K3s Config
    k3s_api_lb_ip       = var.k3s_api_lb_ip
    k3s_ingress_lb_ip   = var.k3s_ingress_lb_ip
    k3s_token           = var.k3s_token
    k3s_init            = var.k3s_init
    k3s_cluster_setting = local.k3s_cluster_setting
    k3s_url             = "${var.k3s_api_lb_ip}:6443"

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
