provider "google" {
  project = "smiling-sweep-495713-r2"
  region  = var.region
  zone    = var.zone
}

variable "region" {
  default = "asia-southeast1" # Region Singapore cho gần VN
}

variable "zone" {
  default = "asia-southeast1-a" # Zone Singapore
}

variable "oslogin_username" {
  description = "OS Login POSIX username (from gcloud compute os-login describe-profile)"
}

