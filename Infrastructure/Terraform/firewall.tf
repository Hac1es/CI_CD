# Mở cửa nội bộ: Các máy trong VPC được phép nói chuyện với nhau 
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-vpc"
  network = google_compute_network.vpc.id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.0.0/16"]
}

# Mở cửa Internet vào Public Subnet (Chỉ máy nào có tag 'public-edge' mới nhận)
resource "google_compute_firewall" "allow_public_web" {
  name    = "allow-public-web"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["public-edge"]
}