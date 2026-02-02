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

variable "image_version" {
  type    = string
  default = "v1"
}

variable "server_type" {
  type    = string
  default = "cpx21"
}

variable "k3s_version" {
  type    = string
}

variable "helm_version" {
  type    = string
}

source "hcloud" "ash" {
  token         = var.hcloud_token
  image         = "ubuntu-24.04"
  location      = "ash"
  server_type   = var.server_type
  ssh_username  = "root"
  snapshot_name = "k3s-base-ash-${var.image_version}"
  snapshot_labels = {
    role    = "k3s-base"
    region  = "ash"
    version = var.image_version
  }
}

source "hcloud" "hil" {
  token         = var.hcloud_token
  image         = "ubuntu-24.04"
  location      = "hil"
  server_type   = var.server_type
  ssh_username  = "root"
  snapshot_name = "k3s-base-hil-${var.image_version}"
  snapshot_labels = {
    role    = "k3s-base"
    region  = "hil"
    version = var.image_version
  }
}

build {
  sources = ["source.hcloud.ash", "source.hcloud.hil"]

  # Upload the infra-bootstrap binary
  # Assumes the compiled binary is in the same folder as this .pkr.hcl file
  provisioner "file" {
    source      = "${path.root}/infra-bootstrap"
    destination = "/usr/local/bin/infra-bootstrap"
  }

  # Main Build Script (Installs, Configs, and Hardcoded Files)
  provisioner "shell" {
    inline = [
      "chmod +x /usr/local/bin/infra-bootstrap",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Basic Tools
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping",

      # Time Sync
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",

      # Install Helm
      "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION='${var.helm_version}' bash",

      # Install gVisor
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/latest/$${ARCH}",
      "wget $${URL}/runsc $${URL}/runsc.sha512",
      "sha512sum -c runsc.sha512",
      "rm -f runsc.sha512",
      "chmod a+rx runsc",
      "mv runsc /usr/local/bin",
      "ln -sf /usr/local/bin/runsc /usr/bin/runsc",

      "wget $${URL}/containerd-shim-runsc-v1 $${URL}/containerd-shim-runsc-v1.sha512",
      "sha512sum -c containerd-shim-runsc-v1.sha512",
      "rm -f containerd-shim-runsc-v1.sha512",
      "chmod a+rx containerd-shim-runsc-v1",
      "mv containerd-shim-runsc-v1 /usr/local/bin",
      "ln -sf /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1",

      # Install Tailscale
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Pre-bake K3s binary
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",

      # DNS Hardening
      "which ufw && ufw disable || true",
      "systemctl stop systemd-resolved",
      "systemctl disable systemd-resolved",
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # ----------------------------------------------------------------
      # CRITICAL FIX: Generic Netplan Route
      # Handles both 'enp7s0' and 'eth0' to ensure network connectivity
      # ----------------------------------------------------------------
      "mkdir -p /etc/netplan",
      "cat > /etc/netplan/99-manual-route.yaml <<EOF",
      "network:",
      "  version: 2",
      "  ethernets:",
      "    all-en:",
      "      match:",
      "        name: \"e*\"",
      "      dhcp4: true",
      "      routes:",
      "        - to: default",
      "          via: 10.0.0.1",
      "          on-link: true",
      "EOF",
      "chmod 600 /etc/netplan/99-manual-route.yaml",
      # ----------------------------------------------------------------

      # gVisor RuntimeClass Manifest
      "mkdir -p /etc/rancher/k3s",
      "mkdir -p /var/lib/rancher/k3s/server/manifests",
      "cat > /var/lib/rancher/k3s/server/manifests/09-gvisor-runtimeclass.yaml <<EOF",
      "apiVersion: node.k8s.io/v1",
      "kind: RuntimeClass",
      "metadata:",
      "  name: gvisor",
      "handler: runsc",
      "EOF",

      # Prepare Service Units
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s server --disable-cloud-controller|g' /etc/systemd/system/k3s.service",

      "systemctl daemon-reload",

      # Load br_netfilter
      "modprobe br_netfilter",
      "echo 'br_netfilter' > /etc/modules-load.d/k3s.conf",

      # Sysctl tuning
      "cat >> /etc/sysctl.d/99-k3s.conf <<EOF",
      "net.ipv4.ip_forward = 1",
      "net.ipv6.conf.all.forwarding = 1",
      "net.bridge.bridge-nf-call-iptables = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      "fs.inotify.max_user_instances = 8192",
      "fs.inotify.max_user_watches = 524288",
      "EOF",

      "sysctl --system",

      # Cleanup
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/netplan/50-cloud-init.yaml",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
