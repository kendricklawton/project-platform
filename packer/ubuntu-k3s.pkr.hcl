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

      # Install tools (including ufw) but DO NOT ENABLE FIREWALL yet
      "apt-get install -y ca-certificates curl python3 wireguard logrotate fail2ban open-iscsi ufw",

      # Install and enable Tailscale for Zero Trust access
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Pre-bake K3s binary to achieve faster 99.95% uptime recovery
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true sh -",

      # Disable systemd-resolved and configure direct DNS
      "systemctl stop systemd-resolved",
      "systemctl disable systemd-resolved",
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # Create k3s-agent service unit (K3s installer only creates 'k3s' for server mode)
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's/k3s server/k3s agent/g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # Sysctl tuning for K3s, Cilium eBPF, and container networking
      "cat >> /etc/sysctl.d/99-k3s.conf <<EOF",
      "net.ipv4.ip_forward = 1",
      "net.ipv6.conf.all.forwarding = 1",
      "net.bridge.bridge-nf-call-iptables = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      "fs.inotify.max_user_instances = 8192",
      "fs.inotify.max_user_watches = 524288",
      "EOF",

      # Cleanup for golden image
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
