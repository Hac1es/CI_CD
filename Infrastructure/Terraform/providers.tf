terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}