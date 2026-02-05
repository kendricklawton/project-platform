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

variable "image" { type = string }
variable "nat_server_type" { type = string }
variable "k3s_server_type" { type = string }
variable "k3s_version" { type = string }
variable "helm_version" { type = string }

# SOURCES: K3S BASE
source "hcloud" "k3s_ash" {
  token         = var.hcloud_token
  image         = var.image
  location      = "ash"
  server_type   = var.k3s_server_type
  ssh_username  = "root"
  snapshot_name = "k3s-base-ash-v1"
  snapshot_labels = {
    role    = "k3s-base"
    region  = "ash"
    version = "v1"
  }
}

source "hcloud" "k3s_hil" {
  token         = var.hcloud_token
  image         = var.image
  location      = "hil"
  server_type   = var.k3s_server_type
  ssh_username  = "root"
  snapshot_name = "k3s-base-hil-v1"
  snapshot_labels = {
    role    = "k3s-base"
    region  = "hil"
    version = "v1"
  }
}

# SOURCES: NAT BASE
source "hcloud" "nat_ash" {
  token         = var.hcloud_token
  image         = var.image
  location      = "ash"
  server_type   = var.nat_server_type
  ssh_username  = "root"
  snapshot_name = "nat-base-ash-v1"
  snapshot_labels = {
    role    = "nat-base"
    region  = "ash"
    version = "v1"
  }
}

source "hcloud" "nat_hil" {
  token         = var.hcloud_token
  image         = var.image
  location      = "hil"
  server_type   = var.nat_server_type
  ssh_username  = "root"
  snapshot_name = "nat-base-hil-v1"
  snapshot_labels = {
    role    = "nat-base"
    region  = "hil"
    version = "v1"
  }
}

# BUILD: K3S
build {
  name    = "k3s"
  sources = ["source.hcloud.k3s_ash", "source.hcloud.k3s_hil"]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Basic Tools
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq",

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

      # DNS Hardening (Force Public DNS, disable systemd stub)
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # Prepare Service Units
      # Create Agent Service from the Server template
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # Load br_netfilter (Required for K3s networking)
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

      # Install & Run Trivy (Security Scanning)
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -",
      "echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/trivy.list",
      "apt-get update && apt-get install -y trivy",

      # Run Scan (Fail build if CRITICAL vulnerabilities found)
      "trivy filesystem --exit-code 1 --severity CRITICAL --ignore-unfixed /",

      # Log Rotation & Limits
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

      # Keep Journald capped at 1GB
      "sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g' /etc/systemd/journald.conf",
      "sed -i 's/#SystemKeepFree=/SystemKeepFree=1G/g' /etc/systemd/journald.conf",

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

# BUILD: NAT
build {
  name    = "nat"
  sources = ["source.hcloud.nat_ash", "source.hcloud.nat_hil"]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # 1. Install Packages (from infra/cloud-init-nat.yaml)
      # Pre-seed debconf to avoid interactive prompts for iptables-persistent
      "echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections",
      "echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections",
      "apt-get install -y iptables-persistent curl jq fail2ban",

      # 2. Security: Disable UFW (We use raw iptables for NAT)
      "ufw disable",

      # 3. Networking: Enable IP Forwarding
      "sysctl -w net.ipv4.ip_forward=1",
      "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",

      # 4. Security: Configure Fail2Ban
      "systemctl enable fail2ban",

      # 5. Software: Install Tailscale (Binaries only)
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # 6. Cleanup
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
