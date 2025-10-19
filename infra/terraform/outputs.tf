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
  description = "External IP address of the instance"
  value       = google_compute_instance.n8n_instance.network_interface[0].access_config[0].nat_ip
}

output "internal_ip" {
  description = "Internal IP address of the instance"
  value       = google_compute_instance.n8n_instance.network_interface[0].network_ip
}

output "static_ip" {
  description = "Reserved static IP address (if enabled)"
  value       = var.use_static_ip ? google_compute_address.n8n_static_ip[0].address : null
}

output "data_disk_name" {
  description = "Name of the persistent data disk"
  value       = google_compute_disk.data_disk.name
}

output "data_disk_size" {
  description = "Size of the data disk in GB"
  value       = google_compute_disk.data_disk.size
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/id_rsa ${var.ssh_user}@${google_compute_instance.n8n_instance.network_interface[0].access_config[0].nat_ip}"
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

    SSH into instance:
    ssh -i ~/.ssh/id_rsa ${var.ssh_user}@${google_compute_instance.n8n_instance.network_interface[0].access_config[0].nat_ip}

    Data disk mounted at: /mnt/data

    Next steps:
    1. Install Docker: curl -fsSL https://get.docker.com | sh
    2. Install Docker Compose: sudo apt install docker-compose-plugin -y
    3. Clone repository and deploy
  EOT
}
