output "instance_name" {
  description = "Name of the compute instance"
  value       = google_compute_instance.n8n_instance.name
}

output "instance_id" {
  description = "ID of the compute instance"
  value       = google_compute_instance.n8n_instance.id
}

output "instance_zone" {
  description = "Zone where the instance is running"
  value       = google_compute_instance.n8n_instance.zone
}

output "external_ip" {
  description = "External IP address (for outbound internet only - no inbound ports open)"
  value       = try(google_compute_instance.n8n_instance.network_interface[0].access_config[0].nat_ip, "No public IP")
}

output "internal_ip" {
  description = "Internal IP address of the instance"
  value       = google_compute_instance.n8n_instance.network_interface[0].network_ip
}

output "data_disk_name" {
  description = "Name of the persistent data disk"
  value       = google_compute_disk.data_disk.name
}

output "data_disk_size" {
  description = "Size of the data disk in GB"
  value       = google_compute_disk.data_disk.size
}

output "ssh_command_iap" {
  description = "SSH command to connect via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.n8n_instance.name} --zone=${google_compute_instance.n8n_instance.zone} --tunnel-through-iap"
}

output "ssh_command_alias" {
  description = "SSH command using configured alias"
  value       = "ssh n8n"
}

output "instance_self_link" {
  description = "Self link to the instance"
  value       = google_compute_instance.n8n_instance.self_link
}

output "machine_type" {
  description = "Machine type of the instance"
  value       = google_compute_instance.n8n_instance.machine_type
}

output "boot_disk_size" {
  description = "Boot disk size in GB"
  value       = google_compute_instance.n8n_instance.boot_disk[0].initialize_params[0].size
}

output "data_mount_point" {
  description = "Mount point for the data disk on the instance"
  value       = "/mnt/data"
}

output "quick_start_guide" {
  description = "Quick start commands for deployment"
  value       = <<-EOT

    SSH into instance via IAP:
    gcloud compute ssh ${google_compute_instance.n8n_instance.name} --zone=${google_compute_instance.n8n_instance.zone} --tunnel-through-iap

    Or using SSH alias:
    ssh n8n

    Internal IP: ${google_compute_instance.n8n_instance.network_interface[0].network_ip}
    Data disk mounted at: /mnt/data

    Note: SSH access via Google Identity-Aware Proxy only (not via public IP)
    See docs/IAP-SETUP.md for setup instructions

    Next steps:
    1. Install Docker: curl -fsSL https://get.docker.com | sh
    2. Install Docker Compose: sudo apt install docker-compose-plugin -y
    3. Clone repository and deploy
  EOT
}
