packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "location" {
  type    = string
  default = "ash"
}

variable "image_version" {
  type    = string
  default = "v1"
}

# Allows matching build hardware to deployment hardware (cpx21 vs cpx31)
variable "server_type" {
  type    = string
  default = "cpx21"
}

source "hcloud" "k3s_base" {
  token         = var.hcloud_token
  image         = "ubuntu-24.04"
  location      = var.location
  server_type   = var.server_type
  ssh_username  = "root"

  # --- FIXED: STATIC NAMING ---
  # Matches Terraform's expectation (e.g., k3s-base-ash-v1)
  # NOTE: You must delete this snapshot in Hetzner UI to rebuild it!
  snapshot_name = "k3s-base-${var.location}-${var.image_version}"

  snapshot_labels = {
    role   = "k3s-base"
    region = var.location
  }
}

build {
  sources = ["source.hcloud.k3s_base"]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y ca-certificates curl python3 wireguard logrotate fail2ban open-iscsi ufw",

      # Install and enable Tailscale for Zero Trust access
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",

      # Pre-bake K3s binary to achieve faster 99.95% uptime recovery
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true sh -",

      # --- ZERO TRUST FIREWALL CONFIG ---

      # 1. Deny all incoming traffic by default
      "ufw default deny incoming",

      # 2. Allow SSH ONLY via the Tailscale interface (VPN)
      "ufw allow in on tailscale0 to any port 22 proto tcp",

      # 3. Allow Internal Cluster Traffic (Subnet ONLY)
      # Replaced 'eth0' (which is Public Internet) with the Private Network CIDR
      "ufw allow from 10.0.0.0/16 to any",

      # 4. Enable Firewall
      "ufw --force enable",
      "apt-get clean"
    ]
  }
}
