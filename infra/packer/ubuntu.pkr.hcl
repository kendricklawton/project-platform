# --- PACKER CONFIGURATION ---
# This block defines the binary requirements. We're using both Hetzner and DigitalOcean
# to maintain multi-cloud parity as defined in the 'project-platform' spec.
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
# These variables are injected via the 'task _packer_build' command in Taskfile.yml.
# We use sensitive = true for tokens to ensure they don't leak in CI/CD logs.
# Default Version
variable "image_version" {
  type    = string
  default = "v1"
}

# Hetzner Cloud Config
variable "hcloud_token" {
  type      = string
  sensitive = true
}
variable "hcloud_server_type" {
  type    = string
}
variable "hcloud_ubuntu_version" {
  type    = string
}

# DigitalOcean Config
variable "docloud_token" {
  type      = string
  sensitive = true
}
variable "docloud_server_type" {
  type    = string
}
variable "docloud_ubuntu_version" {
  type    = string
}

# --- SOURCES (Compute Instances) ---
source "hcloud" "nat_ash" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "ash"
  server_type     = var.hcloud_server_type
  ssh_username    = "root"
  snapshot_name   = "ash-nat-gateway-${var.image_version}"
  snapshot_labels = {
    role     = "nat-gateway"
    location = "ash"
    version  = ${var.image_version}
  }
}

source "hcloud" "nat_hil" {
  token           = var.hcloud_token
  image           = var.hcloud_ubuntu_version
  location        = "hil"
  server_type     = var.hcloud_server_type
  ssh_username    = "root"
  snapshot_name   = "hil-nat-gateway-${var.image_version}"
  snapshot_labels = {
    role     = "nat-gateway"
    location  = "hil"
    version  = ${var.image_version}
  }
}

source "digitalocean" "nat_nyc" {
  api_token     = var.docloud_token
  region        = "nyc3"
  size          = var.docloud_server_type
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "nyc3-nat-gateway-${var.image_version}"
  tags          = ["nat-gateway", "region:nyc", "version:${var.image_version}"]
}

source "digitalocean" "nat_sfo" {
  api_token     = var.docloud_token
  region        = "sfo3"
  size          = var.docloud_server_type
  image         = var.docloud_ubuntu_version
  ssh_username  = "root"
  snapshot_name = "sfo3-nat-gateway-${var.image_version}"
  tags          = ["nat-gateway", "region:sfo", "version:${var.image_version}"]
}

# --- BUILD PIPELINE ---
build {
  name = "nat-gateway"

  # We pull from multiple sources to build images in parallel across clouds.
  # Use 'task packer:hz' or 'task packer:do' to target specific ones.
  sources = [
    "source.hcloud.nat_ash",
    "source.digitalocean.nat_nyc"
  ]

  # Cloud-init can often conflict with apt-get if it's still running updates.
  # This provisioner ensures the VM is actually ready for our script.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "/usr/bin/cloud-init status --wait"
    ]
  }

  # Main Installation Script
  # This transforms a generic Ubuntu image into a dedicated Routing/Security Gateway.
  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Core Utilities
      # - iptables-persistent: Saves NAT rules across reboots
      # - tailscale: The backbone of our secure private network
      # - fail2ban: Basic SSH brute-force protection
      "apt-get install -y ca-certificates curl wget iptables-persistent systemd-timesyncd fping jq fail2ban",

      # Clock sync is vital for Tailscale/Wireguard handshake stability
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",

      # Install Tailscale
      # We clear the state file so each new instance generated from this snapshot
      # is forced to authenticate as a unique node.
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Enable IPv4 Forwarding
      # This is the "magic" that allows this VM to act as a bridge for other servers.
      "sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf",
      "sysctl -p",

      # Hardening: Configure Fail2Ban
      # Since NAT gateways are often edge-facing, we need to punish brute-force SSH attempts.
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

      # Image Optimization & Cleanup
      # We want the final snapshot to be as small as possible to save on storage costs.
      "apt-get autoremove -y",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",

      # Zero out the free space to help the cloud provider's compression algorithm.
      "dd if=/dev/zero of=/EMPTY bs=1M || true",
      "rm -f /EMPTY",
      "sync",

      # Identity Reset
      # CRITICAL: Ensures every VM spawned from this image gets its own unique Machine ID.
      "cloud-init clean --logs",
      "rm -f /etc/netplan/*.yaml",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname",
      "sync"
    ]
  }
}
