# 1. Tạo VPC (VPC Network)
resource "google_compute_network" "vpc" {
  name                    = "project-vpc"
  auto_create_subnetworks = false
}

# 2. Tạo Public Subnet
resource "google_compute_subnetwork" "public" {
  name                     = "public-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.1.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# 3. Tạo Workload Subnet (Private)
resource "google_compute_subnetwork" "workload" {
  name                     = "workload-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.2.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# 4. Tạo Management Subnet
resource "google_compute_subnetwork" "management" {
  name                     = "management-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.3.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Route private instances through bastion for Internet egress
resource "google_compute_route" "private_egress" {
  name                   = "private-egress"
  network                = google_compute_network.vpc.id
  dest_range             = "0.0.0.0/0"
  next_hop_instance      = google_compute_instance.bastion.self_link
  next_hop_instance_zone = var.zone
  tags                   = ["private-egress"]
}