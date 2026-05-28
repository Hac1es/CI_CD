data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# --- 1. Bastion VM Ở PUBLIC SUBNET (Có IP Public) ---
resource "google_compute_instance" "bastion" {
  # checkov:skip=CKV_GCP_38: Sử dụng mã hóa mặc định của Google là đủ rồi
  # checkov:skip=CKV_GCP_36: Bật IP Forwarding để làm NAT Gateway/Edge Router cho project
  # checkov:skip=CKV_GCP_40: Bắt buộc có IP Public để có thể tiếp cận cluster
  name           = "edge-server"
  machine_type   = "e2-small"
  zone           = var.zone
  tags           = ["public-edge"] # Nhận luật Firewall từ Internet
  allow_stopping_for_update = true
  can_ip_forward = true
  desired_status = var.vm_state

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
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
resource "google_compute_instance" "gitlab" {
  # checkov:skip=CKV_GCP_38: Sử dụng mã hóa mặc định của Google là đủ rồi
  name           = "gitlab-server"
  machine_type   = "e2-standard-2"
  zone           = var.zone
  tags           = ["private-egress"]
  allow_stopping_for_update = true
  desired_status = var.vm_state

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.management.id
    # Không có access_config => KHÔNG có IP Public
  }
}

# --- 3. VMs Ở WORKLOAD SUBNET (K3s Master & Worker) ---
resource "google_compute_instance" "k3s_master" {
  # checkov:skip=CKV_GCP_38: Sử dụng mã hóa mặc định của Google là đủ rồi
  name           = "k3s-master"
  machine_type   = "e2-medium"
  zone           = var.zone
  tags           = ["private-egress"]
  allow_stopping_for_update = true
  desired_status = var.vm_state

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
  }
}

resource "google_compute_instance" "k3s_worker" {
  # checkov:skip=CKV_GCP_38: Sử dụng mã hóa mặc định của Google là đủ rồi
  name           = "k3s-worker"
  machine_type   = "e2-medium"
  zone           = var.zone
  tags           = ["private-egress"]
  allow_stopping_for_update = true
  desired_status = var.vm_state

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
  }
}