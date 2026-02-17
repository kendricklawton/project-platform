packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hetznercloud/hcloud"
    }
    digitalocean = {
      version = ">= 1.0.0"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

# HCLOUD CONFIG
variable "hcloud_token" {
  type      = string
  sensitive = true
}
variable "hcloud_image" {
  type = string
  default = "ubuntu-22.04"
}
variable "hcloud_server_type" { type = string }

# DIGITALOCEAN CONFIG
variable "docloud_token" {
  type      = string
  sensitive = true
}
variable "docloud_image" {
  type = string
  default = "ubuntu-22-04-x64"
}
variable "docloud_server_type" { type = string }

# Component Versions
variable "k3s_version" { type = string }
variable "gvisor_version" { type = string }

# --- SOURCES ---

# Hetzner: US East (Ashburn)
source "hcloud" "k3s_ash" {
  token         = var.hcloud_token
  image         = var.hcloud_image
  location      = "ash"
  server_type   = var.hcloud_server_type
  ssh_username  = "root"
  snapshot_name = "ash-k3s-base-v1"
  snapshot_labels = {
    role    = "k3s-base"
    location  = "ash"
    version = "v1"
  }
}


# Hetzner: US West (Hillsboro)
source "hcloud" "k3s_hil" {
  token         = var.hcloud_token
  image         = var.hcloud_image
  location      = "hil"
  server_type   = var.hcloud_server_type
  ssh_username  = "root"
  snapshot_name = "hil-k3s-base-v1"
  snapshot_labels = {
    role    = "k3s-base"
    location  = "hil"
    version = "v1"
  }
}

# DigitalOcean: US East (New York 3)
source "digitalocean" "k3s_nyc" {
  api_token     = var.docloud_token
  region        = "nyc3"
  size          = var.docloud_server_type
  image         = var.docloud_image
  ssh_username  = "root"
  snapshot_name = "nyc3-k3s-base-v1"
  tags          = ["k3s-base", "region:nyc", "version:v1"]
}

# DigitalOcean: US West (San Francisco 3)
source "digitalocean" "k3s_sfo" {
  api_token     = var.docloud_token
  region        = "sfo3"
  size          = var.docloud_server_type
  image         = var.docloud_image
  ssh_username  = "root"
  snapshot_name = "sfo3-k3s-base-v1"
  tags          = ["k3s-base", "region:sfo", "version:v1"]
}

# --- BUILD PIPELINE ---

build {
  name = "k3s"

  sources = [
    "source.hcloud.k3s_ash",
    "source.hcloud.k3s_hil",
    "source.digitalocean.k3s_nyc",
    "source.digitalocean.k3s_sfo"
  ]

  # Wait for Cloud-Init (Critical for DigitalOcean)
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  # 2. Main Installation Script
  provisioner "shell" {
    inline = [
      # Set non-interactive mode
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Core Utilities
      # fail2ban: Defense-in-depth against brute force
      # wireguard: Required for Cilium encryption/peering
      # open-iscsi/nfs-common: Required for storage drivers
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq fail2ban",

      # Enable System Time Synchronization
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",

      # Install Debugging Aliases
      "echo \"alias hstat='kubectl get helmcharts -A'\" >> /root/.bashrc",
      "echo \"alias hdebug='kubectl describe helmchart -n kube-system'\" >> /root/.bashrc",
      "echo \"alias k='kubectl'\" >> /root/.bashrc",

      # Install gVisor (runsc)
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/${var.gvisor_version}/$${ARCH}",
      "wget -q $${URL}/runsc $${URL}/runsc.sha512 || { echo 'Failed to download runsc'; exit 1; }",
      "sha512sum -c runsc.sha512 || { echo 'Checksum verification failed for runsc'; exit 1; }",
      "rm -f runsc.sha512",
      "chmod a+rx runsc",
      "mv runsc /usr/local/bin",
      "ln -sf /usr/local/bin/runsc /usr/bin/runsc",

      "wget -q $${URL}/containerd-shim-runsc-v1 $${URL}/containerd-shim-runsc-v1.sha512 || { echo 'Failed to download containerd-shim-runsc-v1'; exit 1; }",
      "sha512sum -c containerd-shim-runsc-v1.sha512 || { echo 'Checksum verification failed for containerd-shim-runsc-v1'; exit 1; }",
      "rm -f containerd-shim-runsc-v1.sha512",
      "chmod a+rx containerd-shim-runsc-v1",
      "mv containerd-shim-runsc-v1 /usr/local/bin",
      "ln -sf /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1",

      # Install Tailscale (Mesh VPN)
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Pre-download K3s Binary (Binaries only, no start)
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",

      # DNS Hardening (Force Public DNS, disable systemd stub)
      # "rm -f /etc/resolv.conf",
      # "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      # "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # Configure Systemd Services (Prepare Agent Service)
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # Kernel Tuning for Kubernetes
      "modprobe br_netfilter",
      "echo 'br_netfilter' > /etc/modules-load.d/k3s.conf",

      "cat >> /etc/sysctl.d/99-k3s.conf <<EOF",
      "net.ipv4.ip_forward = 1",
      "net.ipv6.conf.all.forwarding = 1",
      "net.bridge.bridge-nf-call-iptables = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      "fs.inotify.max_user_instances = 8192",
      "fs.inotify.max_user_watches = 524288",
      "EOF",
      "sysctl --system",

      # Log Maintenance
      "cat > /etc/logrotate.d/k3s-bootstrap <<EOF",
      "/var/log/tailscale-join.log {",
      "    size 10M",
      "    rotate 5",
      "    compress",
      "    missingok",
      "    notifempty",
      "    copytruncate",
      "}",
      "EOF",

      "sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g' /etc/systemd/journald.conf",
      "sed -i 's/#SystemKeepFree=/SystemKeepFree=1G/g' /etc/systemd/journald.conf",

      # Security: Fail2Ban
      "cat > /etc/fail2ban/jail.local <<EOF",
      "[DEFAULT]",
      "bantime = 1h",
      "findtime = 10m",
      "maxretry = 5",
      "backend = systemd",
      "",
      "[sshd]",
      "enabled = true",
      "EOF",
      "systemctl enable fail2ban",

      "apt-get autoremove -y",

      # This writes zeros to all free space so compression works effectively
      "dd if=/dev/zero of=/EMPTY bs=1M || { echo 'Failed to zero out disk space'; exit 1; }",
      "rm -f /EMPTY",
      "sync",

      "cloud-init clean --logs",
      "rm -f /etc/netplan/*.yaml",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",

      # Cleanup
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "truncate -s 0 /etc/hostname",
      "sync"
    ]
  }
}
