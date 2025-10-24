terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required APIs
resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

# Create a persistent disk for data storage
resource "google_compute_disk" "data_disk" {
  name = "${var.instance_name}-data"
  type = "pd-standard"
  zone = var.zone
  size = var.data_disk_size_gb

  labels = {
    environment = var.environment
    application = "n8n"
  }

  depends_on = [google_project_service.compute_api]
}

# Create the e2-micro compute instance
resource "google_compute_instance" "n8n_instance" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["n8n", "cloudflare-tunnel", var.environment]

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  # Attach the persistent data disk
  attached_disk {
    source      = google_compute_disk.data_disk.id
    device_name = "data"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default"
    # No access_config block = no public IP
    # SSH access via Identity-Aware Proxy only
  }

  metadata = {
    ssh-keys           = "${var.ssh_user}:${var.ssh_public_key}"
    serial-port-enable = "TRUE"  # Enable serial console for emergency access
  }

  # Startup script to format and mount data disk on first boot
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e

    # Check if data disk is already formatted
    if ! blkid /dev/disk/by-id/google-data; then
      echo "Formatting data disk..."
      mkfs.ext4 -F /dev/disk/by-id/google-data
    fi

    # Create mount point
    mkdir -p /mnt/data

    # Add to fstab if not already present
    if ! grep -q "/mnt/data" /etc/fstab; then
      echo "/dev/disk/by-id/google-data /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab
    fi

    # Mount the disk
    mount -a

    # Create application directories
    mkdir -p /mnt/data/n8n
    mkdir -p /mnt/data/postgres
    mkdir -p /mnt/data/backups

    # Set permissions
    chmod -R 755 /mnt/data

    echo "Data disk setup complete"
  EOF

  labels = {
    environment = var.environment
    application = "n8n"
    managed_by  = "terraform"
  }

  # Allow the instance to be stopped for maintenance
  allow_stopping_for_update = true

  depends_on = [
    google_project_service.compute_api,
    google_compute_disk.data_disk
  ]
}

# Firewall rule for SSH access via Identity-Aware Proxy (IAP)
# This is the ONLY SSH access method - no public IP, no direct SSH
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.instance_name}-allow-ssh-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google Identity-Aware Proxy IP range
  # This is a fixed range that IAP uses globally
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["n8n"]

  description = "Allow SSH via Google Identity-Aware Proxy"
}

# Static IP reservation (optional, for stable external access)
resource "google_compute_address" "n8n_static_ip" {
  count = var.use_static_ip ? 1 : 0

  name   = "${var.instance_name}-static-ip"
  region = var.region

  labels = {
    environment = var.environment
    application = "n8n"
  }
}

# Note: If using static IP, you would need to modify the instance network_interface
# This is left as a manual step or can be enhanced with conditional logic
