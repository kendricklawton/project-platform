/*
  =============================================================================
  PROJECT PLATFORM: IMMUTABLE INFRASTRUCTURE BUILDS (GOLDEN IMAGES)
  =============================================================================
  What is this file?
  This is a HashiCorp Packer template. Instead of booting up an empty Linux
  server and running installation scripts every time we want to scale up,
  Packer boots a temporary server, installs all our software, takes a
  "snapshot" (Golden Image) of the hard drive, and then deletes the temporary
  server.

  Terraform will then use these pre-baked snapshots to boot new servers in
  seconds instead of minutes.

  We build two types of images here:
  1. NAT Gateway: A tiny router that handles outbound internet traffic for
     private cluster nodes. Baked fully — cloud-init only injects hostname,
     detects WAN interface, and joins Tailscale at boot.
  2. K3s Node:   A heavy-duty worker/control-plane node pre-loaded with
     Kubernetes, gVisor, and all dependencies.
  =============================================================================
*/

packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

# VARIABLES
variable "k3s_version" {
  type = string
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "hcloud_ubuntu_version" {
  type    = string
}

variable "hcloud_nat_type" {
  type    = string
}

variable "hcloud_k3s_type" {
  type    = string
}

# LOCALS
locals {
  timestamp = formatdate("YYMMDD", timestamp())
}

# SOURCES: NAT GATEWAY
source "hcloud" "nat_ash" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "ash"
  server_type   = var.hcloud_nat_type
  ssh_username  = "root"
  snapshot_name = "ash-nat-gateway-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "nat-gateway"
    location  = "ash"
    version = local.timestamp
  }
}

source "hcloud" "nat_hil" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "hil"
  server_type   = var.hcloud_nat_type
  ssh_username  = "root"
  snapshot_name = "hil-nat-gateway-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "nat-gateway"
    location  = "hil"
    version = local.timestamp
  }
}

# SOURCES: K3S NODE
source "hcloud" "k3s_ash" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "ash"
  server_type   = var.hcloud_k3s_type
  ssh_username  = "root"
  snapshot_name = "ash-k3s-node-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "k3s-node"
    location  = "ash"
    version = local.timestamp
  }
}

source "hcloud" "k3s_hil" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "hil"
  server_type   = var.hcloud_k3s_type
  ssh_username  = "root"
  snapshot_name = "hil-k3s-node-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "k3s-node"
    location = "hil"
    version = local.timestamp
  }
}


# BUILD: NAT GATEWAY
build {
  name    = "nat"
  sources = ["source.hcloud.nat_ash", "source.hcloud.nat_hil"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  # --- PACKAGES & OS CONFIG ---
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      # Pre-seed iptables-persistent to avoid interactive prompts
      "echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections",
      "echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections",

      # Update and Install Packages (Added unattended-upgrades)
      "apt-get update -y",
      "apt-get upgrade -y",
      "apt-get install -y iptables-persistent curl jq fail2ban unattended-upgrades",
    ]
  }

  # --- SECURITY HARDENING ---
  provisioner "shell" {
    inline = [
      # Enable fail2ban and automatic security patches
      "systemctl enable fail2ban",
      "systemctl enable unattended-upgrades",

      # Lock down SSH (Disallow passwords and root login since we use Tailscale SSH)
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "systemctl restart ssh || systemctl restart sshd"
    ]
  }

  # --- KERNEL TUNING FOR HIGH THROUGHPUT NAT ---
  provisioner "shell" {
    inline = [
      "cat << 'EOF' > /etc/sysctl.d/99-nat-tuning.conf",
      "# Enable IP Forwarding",
      "net.ipv4.ip_forward=1",
      "",
      "# TCP BBR Congestion Control for better throughput",
      "net.core.default_qdisc=fq",
      "net.ipv4.tcp_congestion_control=bbr",
      "",
      "# Increase connection tracking table size (Prevent 'table full, dropping packet')",
      "net.netfilter.nf_conntrack_max=1048576",
      "",
      "# Widen the ephemeral port range for NAT translations",
      "net.ipv4.ip_local_port_range=1024 65535",
      "",
      "# Fast recycling of TIME_WAIT sockets",
      "net.ipv4.tcp_tw_reuse=1",
      "EOF",
      "sysctl --system"
    ]
  }

  # --- FIREWALL RULES (Base rules without dynamic MASQUERADE) ---
  provisioner "shell" {
    inline = [
      "cat << 'EOF' > /etc/iptables/rules.v4",
      "*filter",
      ":INPUT ACCEPT [0:0]",
      ":FORWARD ACCEPT [0:0]",
      ":OUTPUT ACCEPT [0:0]",
      "-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT",
      "-A INPUT -i lo -j ACCEPT",
      "-A INPUT -p udp --dport 41641 -j ACCEPT",
      "-A INPUT -s 10.0.0.0/16 -j ACCEPT",
      "-A INPUT -j DROP",
      "-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT",
      "-A FORWARD -s 10.0.0.0/16 -j ACCEPT",
      "COMMIT",
      "*nat",
      ":PREROUTING ACCEPT [0:0]",
      ":INPUT ACCEPT [0:0]",
      ":OUTPUT ACCEPT [0:0]",
      ":POSTROUTING ACCEPT [0:0]",
      "COMMIT",
      "EOF"
    ]
  }

  # --- TAILSCALE ---
  provisioner "shell" {
    inline = [
      # Install Tailscale binaries
      "curl -fsSL https://tailscale.com/install.sh | sh",
      # Ensure the service is enabled to start on boot
      "systemctl enable tailscaled"
    ]
  }

  # --- CLEANUP ---
    provisioner "shell" {
      inline = [
        "apt-get clean",
        "rm -rf /var/lib/apt/lists/*",
        "rm -f /etc/netplan/50-cloud-init.yaml",
        "cloud-init clean --logs --seed",
        "truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id /etc/hostname"
      ]
    }
}

# BUILD: K3S NODE
build {
  name    = "k3s"
  sources = ["source.hcloud.k3s_ash", "source.hcloud.k3s_hil"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  # --- PACKAGES ---
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq",
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true"
    ]
  }

  # --- SECURITY HARDENING (Enforce Tailscale SSH Only) ---
  provisioner "shell" {
    inline = [
      # Disable standard SSH password and root login
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "systemctl restart ssh || systemctl restart sshd"
    ]
  }

  # --- GVISOR ---
  provisioner "shell" {
    inline = [
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
      "ln -sf /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1"
    ]
  }

  # --- TAILSCALE ---
  provisioner "shell" {
    inline = [
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state"
    ]
  }

  # --- K3S BINARY ---
  provisioner "shell" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload"
    ]
  }

  # # --- DNS HARDENING ---
  # provisioner "shell" {
  #   inline = [
  #     "rm -f /etc/resolv.conf",
  #     "printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf"
  #   ]
  # }

  # --- KERNEL TUNING ---
  provisioner "shell" {
    inline = [
      "modprobe br_netfilter",
      "printf 'br_netfilter\n' > /etc/modules-load.d/k3s.conf",
      "echo 'net.ipv4.ip_forward = 1'                    >  /etc/sysctl.d/99-k3s.conf",
      "echo 'net.ipv6.conf.all.forwarding = 1'           >> /etc/sysctl.d/99-k3s.conf",
      "echo 'net.bridge.bridge-nf-call-iptables = 1'     >> /etc/sysctl.d/99-k3s.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1'    >> /etc/sysctl.d/99-k3s.conf",
      "echo 'fs.inotify.max_user_instances = 8192'       >> /etc/sysctl.d/99-k3s.conf",
      "echo 'fs.inotify.max_user_watches = 524288'       >> /etc/sysctl.d/99-k3s.conf",
      "sysctl --system"
    ]
  }

  # --- TRIVY SECURITY SCAN ---
  provisioner "shell" {
    inline = [
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -",
      "echo \"deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main\" | tee /etc/apt/sources.list.d/trivy.list",
      "apt-get update && apt-get install -y trivy",
      "trivy filesystem --exit-code 1 --severity CRITICAL --ignore-unfixed /"
    ]
  }

  # --- LOG ROTATION ---
  provisioner "shell" {
    inline = [
      "echo '/var/log/tailscale-join.log {'           >  /etc/logrotate.d/k3s-bootstrap",
      "echo '    size 10M'                            >> /etc/logrotate.d/k3s-bootstrap",
      "echo '    rotate 5'                            >> /etc/logrotate.d/k3s-bootstrap",
      "echo '    compress'                            >> /etc/logrotate.d/k3s-bootstrap",
      "echo '    missingok'                           >> /etc/logrotate.d/k3s-bootstrap",
      "echo '    notifempty'                          >> /etc/logrotate.d/k3s-bootstrap",
      "echo '    copytruncate'                        >> /etc/logrotate.d/k3s-bootstrap",
      "echo '}'                                       >> /etc/logrotate.d/k3s-bootstrap",
      "sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/'     /etc/systemd/journald.conf",
      "sed -i 's/#SystemKeepFree=/SystemKeepFree=1G/' /etc/systemd/journald.conf"
    ]
  }


  # --- CLEANUP ---
    provisioner "shell" {
      inline = [
        "apt-get clean",
        "rm -rf /var/lib/apt/lists/*",
        "rm -f /etc/netplan/50-cloud-init.yaml",
        "cloud-init clean --logs --seed",
        "truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id /etc/hostname"
      ]
    }
}
