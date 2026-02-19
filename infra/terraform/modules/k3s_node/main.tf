terraform {
  required_version = ">= 1.5.0"
}

locals {
  # Logic to determine the K3s startup flag
  k3s_cluster_setting = var.k3s_init ? "cluster-init: true" : "server: https://${var.k3s_api_lb_ip}:6443"

  # Generator script for the manifests
  manifest_injector_script = join("\n", [
    for filename, content in var.manifests :
    "echo '${base64encode(content)}' | base64 -d > /var/lib/rancher/k3s/server/manifests/${filename}"
  ])

  # Select the correct template based on role
  template_file = var.node_role == "server" ? "${path.module}/templates/cloud-init-server.yaml" : "${path.module}/templates/cloud-init-agent.yaml"
}
