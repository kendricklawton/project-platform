packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hetznercloud/hcloud"
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

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "location" {
  type    = string
  default = "ash"
}

variable "talos_version" {
  type    = string
  default = "v1.7.6"
}

locals {
  # The official pre-compiled Talos image specifically designed for Hetzner Cloud
  image_url = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/hcloud-amd64.raw.xz"
}

source "hcloud" "talos_base" {
  token        = var.hcloud_token

  # CRITICAL: Booting into 'linux64' rescue mode bypasses the standard OS installation
  rescue       = "linux64"
  image        = "ubuntu-22.04" # This OS is completely overwritten, so the choice doesn't matter
  server_type  = "cpx11"        # The cheapest node type just to perform the build
  location     = var.location
  ssh_username = "root"

  snapshot_name = "talos-base-${var.location}-${var.talos_version}"

  # These labels perfectly match the data block in the main.tf
  snapshot_labels = {
    role     = "talos-base"
    location = "${var.location}"
    version  = "${var.talos_version}"
  }
}

build {
  name = "talos"

  sources = ["source.hcloud.talos_base"]

  provisioner "shell" {
    inline = [
      "echo '--- Downloading Talos OS ---'",
      "wget -qO /tmp/talos.raw.xz ${local.image_url}",

      "echo '--- Writing Talos directly to the raw disk ---'",
      "xz -d -c /tmp/talos.raw.xz | dd of=/dev/sda bs=4M",
      "sync",

      "echo '--- Talos OS successfully written! ---'"
    ]
  }
}
