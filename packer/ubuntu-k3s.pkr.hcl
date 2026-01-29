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

# --- BUILD SOURCES ---
# We build identical images for both US East (Ashburn) and US West (Hillsboro)
# so we can deploy clusters in either region without latency.

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

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update && apt-get upgrade -y",

      # 1. Install Basic Tools
      # NOTE: We purposely OMIT 'ufw' here. K3s manages its own firewall rules.
      # NOTE: We OMIT 'open-iscsi' for now.
      #       If we later decide to run Databases (StatefulSets) that need
      #       Persistent Volumes (Hetzner CSI), we MUST add 'open-iscsi' back to this list.
      "apt-get install -y ca-certificates curl wget python3 wireguard logrotate",

      # 2. INSTALL GVISOR (The Sandbox)
      # We install the 'runsc' binary now so it is baked into the image.
      # Agent nodes will use this to sandbox untrusted code.
      # Server nodes will have the binary but won't use it (config removed in cloud-init).
      # NOTE: We use '$${VAR}' to prevent Packer from trying to interpret the variable.
      #       This passes '${ARCH}' literally to the bash shell.
      "ARCH=$(uname -m)",
      "URL=https://storage.googleapis.com/gvisor/releases/release/latest/$${ARCH}",

      # Download runsc (The Kernel)
      # REASON: We use 'wget' here because we need to DOWNLOAD files to disk.
      # wget is better for multi-file downloads and saving artifacts compared to curl.
      "wget $${URL}/runsc $${URL}/runsc.sha512",
      "sha512sum -c runsc.sha512",
      "rm -f runsc.sha512",
      "chmod a+rx runsc",
      "mv runsc /usr/local/bin",
      "ln -s /usr/local/bin/runsc /usr/bin/runsc",

      # Download containerd-shim (The Bridge)
      # This adapter allows K3s to talk to gVisor.
      "wget $${URL}/containerd-shim-runsc-v1 $${URL}/containerd-shim-runsc-v1.sha512",
      "sha512sum -c containerd-shim-runsc-v1.sha512",
      "rm -f containerd-shim-runsc-v1.sha512",
      "chmod a+rx containerd-shim-runsc-v1",
      "mv containerd-shim-runsc-v1 /usr/local/bin",
      "ln -s /usr/local/bin/containerd-shim-runsc-v1 /usr/bin/containerd-shim-runsc-v1",

      # 3. Install Tailscale
      # REASON: We use 'curl | sh' here because we want to STREAM the script
      # directly to the shell interpreter without saving the .sh file to disk.
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "systemctl enable tailscaled",
      "rm -f /var/lib/tailscale/tailscaled.state",

      # 4. Pre-bake K3s binary
      # We install the binary now to speed up boot time (no downloading 50MB on startup).
      # INSTALL_K3S_SKIP_ENABLE=true: Critical! Prevents K3s from starting immediately.
      # We want cloud-init to configure it (Server vs Agent) before it starts.
      "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true sh -",

      # 5. DNS Hardening
      # We remove 'systemd-resolved' because it acts as a caching stub resolver
      # that often creates loopbacks/conflicts with Kubernetes CoreDNS.
      # We replace it with a "dumb" file pointing to reliable global DNS.
      "systemctl stop systemd-resolved",
      "systemctl disable systemd-resolved",
      "rm -f /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",

      # 6. Create k3s-agent service unit
      # By default, the K3s installer creates a 'server' service.
      # We clone and modify it to create an 'agent' service so our Agents
      # can start up cleanly using 'systemctl start k3s-agent'.
      "cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s-agent.service",
      "sed -i 's|/usr/local/bin/k3s \\\\|/usr/local/bin/k3s agent \\\\|g' /etc/systemd/system/k3s-agent.service",
      "sed -i 's|server|agent|g' /etc/systemd/system/k3s-agent.service",
      "systemctl daemon-reload",

      # 7. Sysctl tuning
      # These are kernel parameters required for Kubernetes networking.
      # - ip_forward: Allows packets to traverse the node (essential for Pod-to-Pod).
      # - fs.inotify: Increases file watch limits (essential for logging and storage).
      "cat >> /etc/sysctl.d/99-k3s.conf <<EOF",
      "net.ipv4.ip_forward = 1",
      "net.ipv6.conf.all.forwarding = 1",
      "net.bridge.bridge-nf-call-iptables = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      "fs.inotify.max_user_instances = 8192",
      "fs.inotify.max_user_watches = 524288",
      "EOF",

      # 8. Cleanup
      # Remove temporary files and logs to keep the golden image small.
      # We also reset the hostname so each new VM generates a unique one on boot.
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs --seed",
      "rm -f /etc/machine-id /var/lib/dbus/machine-id",
      "truncate -s 0 /etc/hostname"
    ]
  }
}
