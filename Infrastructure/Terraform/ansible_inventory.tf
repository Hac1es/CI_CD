resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../Ansible/inventory.yml")
  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    oslogin_username       = var.oslogin_username
    bastion_public_ip      = google_compute_instance.public_edge.network_interface[0].access_config[0].nat_ip
    jenkins_private_ip     = google_compute_instance.jenkins.network_interface[0].network_ip
    harbor_private_ip      = google_compute_instance.harbor.network_interface[0].network_ip
    k3s_master_private_ip  = google_compute_instance.k3s_master.network_interface[0].network_ip
    k3s_worker_private_ip  = google_compute_instance.k3s_worker.network_interface[0].network_ip
  })
}
