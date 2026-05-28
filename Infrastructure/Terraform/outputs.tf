output "public_edge_ephemeral_ip" {
  description = "Ephemeral public IP of the public-edge-proxy VM"
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}
