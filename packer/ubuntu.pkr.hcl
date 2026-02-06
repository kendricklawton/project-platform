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
variable "k3s_server_type" { type = string }
variable "k3s_version" { type = string }
variable "gvisor_version" { type = string }

# Source: Ashburn, VA (US East)
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

# Source: Hillsboro, OR (US West)
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

build {
  name    = "k3s"
  sources = ["source.hcloud.k3s_ash", "source.hcloud.k3s_hil"]

  provisioner "shell" {
    inline = [
      # Set non-interactive mode to prevent apt-get from asking questions
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # Install Core Utilities
      # fail2ban: Added for defense-in-depth against brute force attacks
      # wireguard: Required for Cilium encryption or direct peering
      # open-iscsi/nfs-common: Required for longhorn or other storage drivers
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate open-iscsi nfs-common cryptsetup systemd-timesyncd fping jq fail2ban",

      # Enable System Time Synchronization
      "systemctl enable systemd-timesyncd",
      "timedatectl set-ntp true",

      # Install Debugging Aliases
      # Since we removed the Helm binary, these aliases help monitor the K3s Helm Controller.
      "echo \"alias hstat='kubectl get helmcharts -A'\" >> /root/.bashrc",
      "echo \"alias hdebug='kubectl describe helmchart -n kube-system'\" >> /root/.bashrc",
      "echo \"alias k='kubectl'\" >> /root/.bashrc",

      # Install gVisor (runsc)
      # This downloads the secure runtime sandbox binaries.
      # Note: This only installs the binary; K3s configuration happens in the cloud-init templates.
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/${var.gvisor_version}/${ARCH}",
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

      # Install Tailscale (Mesh VPN)
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      # Remove state so every new node generates a fresh ID on first boot
      "rm -f /var/lib/tailscale/tailscaled.state",

      # Pre-download K3s Binary
      # We install the binary now to speed up boot times.
      # INSTALL_K3S_SKIP_ENABLE=true prevents it from starting immediately during the build.
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_VERSION='${var.k3s_version}' sh -",

      # Hardening: DNS Configuration
      # We force Cloudflare/Google DNS to avoid reliance on ISP/Hetzner default resolvers.
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # Configure Systemd Services
      # Create a dedicated k3s-agent service definition to allow flexible role switching.
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s server|/usr/local/bin/k3s agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # Kernel Tuning for Kubernetes
      # Enable bridging and IP forwarding required for CNI plugins (Cilium/Flannel).
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

      # Security: Vulnerability Scanning (Trivy)
      # Installs Trivy and performs a filesystem scan.
      # The build will FAIL if critical vulnerabilities are found, ensuring a clean gold image.
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -",
      "echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/trivy.list",
      "apt-get update && apt-get install -y trivy",
      "trivy filesystem --exit-code 1 --severity CRITICAL --ignore-unfixed /",

      # Log Maintenance
      # Rotate the Tailscale join log to prevent disk fill-up if bootstrapping loops.
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

      # Cap Journald usage to 1GB to prevent logs from eating the entire disk over time.
      "sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g' /etc/systemd/journald.conf",
      "sed -i 's/#SystemKeepFree=/SystemKeepFree=1G/g' /etc/systemd/journald.conf",

      # Security: Fail2Ban Configuration
      # We explicitly set backend=systemd because modern Ubuntu uses Journald, not auth.log.
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

      # Final Cleanup
      # Remove machine-specific IDs so they are regenerated unique per node.
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/netplan/50-cloud-init.yaml",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
