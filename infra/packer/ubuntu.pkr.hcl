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

# --- VARIABLES ---
variable "image_version" {
  type = string
  default = "v1"
}

variable "docloud_token" {
  type = string
  sensitive = true
}

variable "docloud_ubuntu_version" {
  type = string
}

variable "hcloud_token" {
  type = string
  sensitive = true
}

variable "hcloud_ubuntu_version" {
  type = string
}

# ADDED: Missing version variables for K3s Node build
variable "gvisor_version" {
  type = string
}
variable "k3s_version" {
  type = string
}

# --- SOURCES (NAT GATEWAYS) ---
source "hcloud" "nat_ash" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "ash"
  server_type     = "cpx11"
  ssh_username    = "root"
  snapshot_name   = "ash-nat-base-image-${var.image_version}"
  snapshot_labels = { role = "nat-gateway", location = "ash", version = "${var.image_version}" }
}

source "hcloud" "nat_hil" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "hil"
  server_type     = "cpx11"
  ssh_username    = "root"
  snapshot_name   = "hil-nat-gateway-${var.image_version}"
  snapshot_labels = { role = "nat-gateway", location = "hil", version = "${var.image_version}" }
}

source "digitalocean" "nat_nyc" {
  api_token     = var.docloud_token
  region        = "nyc3"
  size          = "s-1vcpu-1gb"
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "nyc3-nat-gateway-${var.image_version}"
  tags          = ["nat-gateway", "region:nyc", "version:${var.image_version}"]
}

source "digitalocean" "nat_sfo" {
  api_token     = var.docloud_token
  region        = "sfo3"
  size          = "s-1vcpu-1gb"
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "sfo3-nat-gateway-${var.image_version}"
  tags          = ["nat-gateway", "region:sfo", "version:${var.image_version}"]
}

# --- SOURCES (K3S NODES) ---
source "hcloud" "k3s_ash" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "ash"
  server_type     = "cpx11"
  ssh_username    = "root"
  snapshot_name   = "ash-k3s-node-${var.image_version}"
  snapshot_labels = { role = "k3s-node", location = "ash", version = "${var.image_version}" }
}

source "hcloud" "k3s_hil" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "hil"
  server_type     = "cpx11"
  ssh_username    = "root"
  snapshot_name   = "hil-k3s-node-${var.image_version}"
  snapshot_labels = { role = "k3s-node", location = "hil", version = "${var.image_version}" }
}

source "digitalocean" "k3s_nyc" {
  api_token     = var.docloud_token
  region        = "nyc3"
  size          = "s-1vcpu-1gb"
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "nyc3-k3s-node-${var.image_version}"
  tags          = ["k3s-node", "region:nyc", "version:${var.image_version}"]
}

source "digitalocean" "k3s_sfo" {
  api_token     = var.docloud_token
  region        = "sfo3"
  size          = "s-1vcpu-1gb"
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "sfo3-k3s-node-${var.image_version}"
  tags          = ["k3s-node", "region:sfo", "version:${var.image_version}"]
}

# --- BUILD PIPELINES ---

build {
  name = "nat-gateway"
  sources = [
    "source.hcloud.nat_ash",
    "source.hcloud.nat_hil",
    "source.digitalocean.nat_sfo",
    "source.digitalocean.nat_nyc",
  ]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y ca-certificates curl wget wireguard iptables-persistent systemd-timesyncd fping jq fail2ban","apt-get install -y ca-certificates curl wget wireguard iptables-persistent systemd-timesyncd fping jq fail2ban",
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",
      "sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf",
      "sysctl -p",
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
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "dd if=/dev/zero of=/EMPTY bs=1M || true",
      "rm -f /EMPTY",
      "sync",
      "cloud-init clean --logs",
      "rm -f /etc/netplan/*.yaml",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id", # FIXED: Remove instead of truncate
      "truncate -s 0 /etc/hostname",
      "sync"
    ]
  }
}

build {
  name = "k3s-node"
  sources = [
    "source.hcloud.k3s_ash",
    "source.hcloud.k3s_hil",
    "source.digitalocean.k3s_nyc",
    "source.digitalocean.k3s_sfo"
  ]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq fail2ban",
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",
      "echo \"alias hstat='kubectl get helmcharts -A'\" >> /root/.bashrc",
      "echo \"alias hdebug='kubectl describe helmchart -n kube-system'\" >> /root/.bashrc",
      "echo \"alias k='kubectl'\" >> /root/.bashrc",
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/${var.gvisor_version}/$${ARCH}",
      "wget -q $${URL}/runsc $${URL}/runsc.sha512",
      "sha512sum -c runsc.sha512",
      "rm -f runsc.sha512",
      "chmod a+rx runsc",
      "mv runsc /usr/local/bin",
      "ln -sf /usr/local/bin/runsc /usr/bin/runsc",
      "wget -q $${URL}/containerd-shim-runsc-v1 $${URL}/containerd-shim-runsc-v1.sha512",
      "sha512sum -c containerd-shim-runsc-v1.sha512",
      "rm -f containerd-shim-runsc-v1.sha512",
      "chmod a+rx containerd-shim-runsc-v1",
      "mv containerd-shim-runsc-v1 /usr/local/bin",
      "ln -sf /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1",
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",
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
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "dd if=/dev/zero of=/EMPTY bs=1M || true",
      "rm -f /EMPTY",
      "sync",
      "cloud-init clean --logs",
      "rm -f /etc/netplan/*.yaml",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id", # FIXED: Remove instead of truncate
      "truncate -s 0 /etc/hostname",
      "sync"
    ]
  }
}
