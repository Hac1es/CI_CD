resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../Ansible/inventory.ini")
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    oslogin_username      = var.oslogin_username
    bastion_public_ip     = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
    gitlab_private_ip     = google_compute_instance.gitlab.network_interface[0].network_ip
    k3s_master_private_ip = google_compute_instance.k3s_master.network_interface[0].network_ip
    k3s_worker_private_ip = google_compute_instance.k3s_worker.network_interface[0].network_ip
  })
}
