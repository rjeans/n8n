variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for compute instance"
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "Name of the compute instance"
  type        = string
  default     = "n8n-server"
}

variable "machine_type" {
  description = "GCP machine type (e2-micro for free tier)"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = can(regex("^e2-(micro|small|medium)", var.machine_type))
    error_message = "Machine type should be an e2 series instance (e.g., e2-micro, e2-small)."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "boot_disk_image" {
  description = "Boot disk image (Ubuntu LTS recommended)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10

  validation {
    condition     = var.boot_disk_size_gb >= 10 && var.boot_disk_size_gb <= 100
    error_message = "Boot disk size must be between 10 and 100 GB."
  }
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB for persistent storage"
  type        = number
  default     = 20

  validation {
    condition     = var.data_disk_size_gb >= 10 && var.data_disk_size_gb <= 100
    error_message = "Data disk size must be between 10 and 100 GB."
  }
}

variable "ssh_user" {
  description = "SSH username for accessing the instance"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
  sensitive   = true
}

# Note: my_ip and ssh_source_ranges variables removed in Phase 2
# SSH access is now exclusively via Google Identity-Aware Proxy (IAP)
# No IP whitelisting needed - access controlled via GCP IAM permissions

variable "use_static_ip" {
  description = "Whether to use a static external IP address"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}
