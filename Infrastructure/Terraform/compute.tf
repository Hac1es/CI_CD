data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# --- 1. Bastion VM Ở PUBLIC SUBNET (Có IP Public) ---
resource "google_compute_instance" "public_edge" {
  name         = "edge-server"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["public-edge"] # Nhận luật Firewall từ Internet
  can_ip_forward = true
  desired_status = var.vm_state

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    access_config {} # Dòng này cấp IP Public
  }
}

# --- 2. VMs Ở MANAGEMENT SUBNET ---
resource "google_compute_instance" "jenkins" {
  name         = "jenkins-server"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["private-egress"]
  desired_status = var.vm_state

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.management.id
    # Không có access_config => KHÔNG có IP Public
  }
}

resource "google_compute_instance" "harbor" {
  name         = "harbor-registry"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["private-egress"]
  desired_status = var.vm_state

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.management.id
  }
}

# --- 3. VMs Ở WORKLOAD SUBNET (K3s Master & Worker) ---
resource "google_compute_instance" "k3s_master" {
  name         = "k3s-master"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["private-egress"]
  desired_status = var.vm_state

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
  }
}

resource "google_compute_instance" "k3s_worker" {
  name         = "k3s-worker"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["private-egress"]
  desired_status = var.vm_state

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
  }
}