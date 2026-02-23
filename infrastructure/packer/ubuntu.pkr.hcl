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
  1. NAT Gateway: A tiny router that handles outbound internet traffic.
  2. K3s Node: A heavy-duty worker/control-plane node pre-loaded with Kubernetes.
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

# -----------------------------------------------------------------------------
# VARIABLES
# These values are passed in from our Taskfile or CI/CD pipeline.
# -----------------------------------------------------------------------------

# K3s Version (The specific release of Kubernetes we are baking in)
variable "k3s_version" {
  type      = string
}

# DigitalOcean (Included for future multi-cloud expansion)
variable "docloud_token" {
  type      = string
  sensitive = true
}

variable "docloud_ubuntu_version" {
  type    = string
  default = ""
}

variable "docloud_k3s_type" {
  type    = string
  default = ""
}

variable "docloud_nat_type" {
  type    = string
  default = ""
}

# Hetzner Cloud (Our primary bare-metal provider)
variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "hcloud_ubuntu_version" {
  type    = string
  default = ""
}

variable "hcloud_nat_type" {
  type    = string
  default = ""
}

variable "hcloud_k3s_type" {
  type    = string
  default = ""
}


# -----------------------------------------------------------------------------
# LOCALS
# This block generates our dynamic timestamp when the build starts.
# -----------------------------------------------------------------------------
locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
}

# -----------------------------------------------------------------------------
# SOURCES
# A "source" defines the temporary virtual machine that Packer will spin up
# to run our installation scripts. We define separate sources for different
# regions (ash = Ashburn, hil = Hillsboro) to avoid cross-region bandwidth costs.
# -----------------------------------------------------------------------------

# SOURCES: K3S BASE
source "hcloud" "k3s_ash" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "ash"
  server_type   = var.hcloud_k3s_type
  ssh_username  = "root"
  snapshot_name = "k3s-node-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "k3s-node"
    region  = "ash"
    version = local.timestamp
  }
}

source "hcloud" "k3s_hil" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "hil"
  server_type   = var.hcloud_k3s_type
  ssh_username  = "root"
  snapshot_name = "k3s-node-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "k3s-node"
    region  = "hil"
    version = local.timestamp
  }
}

# SOURCES: NAT BASE
source "hcloud" "nat_ash" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "ash"
  server_type   = var.hcloud_nat_type
  ssh_username  = "root"
  snapshot_name = "nat-gateway-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "nat-gateway"
    region  = "ash"
    version = local.timestamp
  }
}

source "hcloud" "nat_hil" {
  token         = var.hcloud_token
  image         = var.hcloud_ubuntu_version
  location      = "hil"
  server_type   = var.hcloud_nat_type
  ssh_username  = "root"
  snapshot_name = "nat-gateway-ubuntu-amd64-${local.timestamp}"
  snapshot_labels = {
    role    = "nat-gateway"
    region  = "hil"
    version = local.timestamp
  }
}

# -----------------------------------------------------------------------------
# BUILD: NAT GATEWAY
# This block connects to the NAT sources above and runs the shell scripts
# required to turn a vanilla Ubuntu server into a hardened network router.
# -----------------------------------------------------------------------------
build {
  name    = "nat"
  sources = ["source.hcloud.nat_ash", "source.hcloud.nat_hil"]

  # --- CLOUD-INIT WAITER (LOCK PREVENTION) ---
  # When a fresh Ubuntu VM boots, it runs background tasks (like security updates)
  # which temporarily lock the apt/dpkg database. We must pause Packer until
  # these are done, otherwise our `apt-get` commands will crash with an error.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  provisioner "shell" {
    inline = [
      # Prevents 'apt-get' from freezing the build by asking for user input (like Y/N prompts)
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Pre-seed debconf to avoid interactive UI prompts for iptables-persistent
      "echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections",
      "echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections",
      "apt-get install -y iptables-persistent curl jq fail2ban",

      # Security: Disable UFW (Uncomplicated Firewall)
      # UFW often overwrites custom routing rules. We use raw iptables for NAT instead.
      "ufw disable",

      # Networking: Enable IP Forwarding
      # This is the most critical step for a router. It tells the Linux kernel
      # that it is allowed to pass network traffic from one interface to another.
      "sysctl -w net.ipv4.ip_forward=1",
      "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",

      # Security: Configure Fail2Ban (protects SSH port from brute force attacks)
      "systemctl enable fail2ban",

      # Install Tailscale (VPN)
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      # CRITICAL: We delete the state file so the snapshot doesn't save the temporary
      # build server's VPN identity. Every new server needs a fresh identity.
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Cleanup & Un-provisioning
      # We wipe all temporary logs, caches, and unique machine IDs so that when
      # Terraform clones this image, the new instances don't have IP/MAC conflicts.
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/netplan/50-cloud-init.yaml",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}

# -----------------------------------------------------------------------------
# BUILD: K3S NODE
# This block builds our heavy-duty Kubernetes nodes. It pre-downloads all the
# massive binaries (like K3s and gVisor) so they boot instantly in production.
# -----------------------------------------------------------------------------
build {
  name    = "k3s"
  sources = ["source.hcloud.k3s_ash", "source.hcloud.k3s_hil"]

  # --- CLOUD-INIT WAITER ---
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Basic Tools
      # open-iscsi & nfs-common are required for Kubernetes to attach cloud hard drives.
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq",

      # Time Sync (Crucial for distributed databases like Etcd and TLS certificates)
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",

      # Install gVisor (runsc)
      # gVisor creates a highly secure sandbox around containers. We use this
      # to safely run untrusted code on our platform without risking the host OS.
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/latest/$${ARCH}",
      "wget $${URL}/runsc $${URL}/runsc.sha512",
      "sha512sum -c runsc.sha512",
      "rm -f runsc.sha512",
      "chmod a+rx runsc",
      "mv runsc /usr/local/bin",
      "ln -sf /usr/local/bin/runsc /usr/bin/runsc",

      # containerd-shim connects Kubernetes (containerd) to the gVisor sandbox.
      "wget $${URL}/containerd-shim-runsc-v1 $${URL}/containerd-shim-runsc-v1.sha512",
      "sha512sum -c containerd-shim-runsc-v1.sha512",
      "rm -f containerd-shim-runsc-v1.sha512",
      "chmod a+rx containerd-shim-runsc-v1",
      "mv containerd-shim-runsc-v1 /usr/local/bin",
      "ln -sf /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1",

      # Install Tailscale (VPN)
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      # CRITICAL: We delete the state file so the snapshot doesn't save the temporary
      # build server's VPN identity. Every new server needs a fresh identity.
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Pre-bake K3s binary (The "Air-Gapped" Approach)
      # INSTALL_K3S_SKIP_ENABLE=true installs the binary but STOPS systemd from
      # starting the cluster. This allows Terraform to inject the config later.
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",

      # DNS Hardening (Force Public DNS, disable systemd stub for reliability)
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # Prepare Service Units
      # The installer only makes a 'k3s.service' (server) file. We copy it to create
      # a dedicated 'k3s-agent.service' file so this image can be used as a worker too.
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # Load br_netfilter (Required by Kubernetes/Cilium to route pod traffic)
      "modprobe br_netfilter",
      "echo 'br_netfilter' > /etc/modules-load.d/k3s.conf",

      # Sysctl Kernel Tuning
      "cat >> /etc/sysctl.d/99-k3s.conf <<EOF",
      "net.ipv4.ip_forward = 1",
      "net.ipv6.conf.all.forwarding = 1",
      "net.bridge.bridge-nf-call-iptables = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      # Maximize inotify limits: Crucial for apps watching the file system.
      # Without this, the Kubelet will eventually run out of handles and crash.
      "fs.inotify.max_user_instances = 8192",
      "fs.inotify.max_user_watches = 524288",
      "EOF",

      "sysctl --system",

      # Install & Run Trivy (Security Scanning)
      # This ensures our golden image is free of critical OS vulnerabilities before saving.
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -",
      "echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/trivy.list",
      "apt-get update && apt-get install -y trivy",

      # Run Scan (Will instantly fail the Packer build if CRITICAL vulnerabilities exist)
      "trivy filesystem --exit-code 1 --severity CRITICAL --ignore-unfixed /",

      # Log Rotation & Limits
      # Without limits, busy cluster logs can consume the entire NVMe drive.
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

      # Cleanup & Un-provisioning
      # We wipe all temporary logs, caches, and unique machine IDs so that when
      # Terraform clones this image, the new instances don't have IP/MAC conflicts.
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/netplan/50-cloud-init.yaml",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
