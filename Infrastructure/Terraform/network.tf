# 1. Tạo VPC (VPC Network)
resource "google_compute_network" "vpc" {
  name                    = "project-vpc"
  auto_create_subnetworks = false
}

# 2. Tạo Public Subnet
resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.1.0/24"
}

# 3. Tạo Workload Subnet (Private)
resource "google_compute_subnetwork" "workload" {
  name          = "workload-subnet-private"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.2.0/24"
  private_ip_google_access = true
}

# 4. Tạo Management Subnet
resource "google_compute_subnetwork" "management" {
  name          = "management-subnet-private"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.3.0/24"
  private_ip_google_access = true
}