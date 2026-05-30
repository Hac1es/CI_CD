# Mở cửa nội bộ: Các máy trong VPC được phép nói chuyện với nhau 
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-vpc"
  network = google_compute_network.vpc.id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.0.0/16"]
}

# Chặn traffic từ Workload sang Management
resource "google_compute_firewall" "barrier_2_to_3" {
  name    = "barrier-2-to-3"
  network = google_compute_network.vpc.id

  direction = "INGRESS"

  source_ranges      = ["10.0.2.0/24"]
  destination_ranges = ["10.0.3.0/24"]

  deny {
    protocol = "all"
  }
}

# Cho phép K3s/Runner trong Workload gọi GitLab API và Registry nội bộ.
# Priority cao hơn barrier để chỉ mở đúng các port CI/CD cần thiết.
resource "google_compute_firewall" "allow_workload_to_gitlab_ci" {
  name     = "allow-workload-to-gitlab-ci"
  network  = google_compute_network.vpc.id
  priority = 900

  direction = "INGRESS"

  source_ranges = ["10.0.2.0/24"]
  target_tags   = ["gitlab-server"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "5000"]
  }
}

# Cho phép K3s/Runner trong Workload gọi SonarQube để chạy SAST/Quality Gate.
# Priority cao hơn barrier để chỉ mở đúng port SonarQube cần thiết.
resource "google_compute_firewall" "allow_workload_to_sast" {
  name     = "allow-workload-to-sast"
  network  = google_compute_network.vpc.id
  priority = 900

  direction = "INGRESS"

  source_ranges = ["10.0.2.0/24"]
  target_tags   = ["sast-server"]

  allow {
    protocol = "tcp"
    ports    = ["9000"]
  }
}

# Chặn traffic từ Management sang Workload
resource "google_compute_firewall" "barrier_3_to_2" {
  name    = "barrier-3-to-2"
  network = google_compute_network.vpc.id

  direction = "INGRESS"

  source_ranges      = ["10.0.3.0/24"]
  destination_ranges = ["10.0.2.0/24"]

  deny {
    protocol = "all"
  }
}

# Mở cửa Internet vào Public Subnet (Chỉ máy nào có tag 'public-edge' mới nhận)
resource "google_compute_firewall" "allow_public_web" {
  # checkov:skip=CKV_GCP_106: Bắt buộc mở Port 80 để làm Web công cộng và redirect traffic sang HTTPS
  # checkov:skip=CKV_GCP_2: Chấp nhận mở SSH công cộng cho Bastion ở môi trường Lab di động
  name    = "allow-public-web"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["public-edge"]
}
