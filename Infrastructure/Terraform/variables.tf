variable "region" {
  default = "asia-southeast1" # Region Singapore cho gần VN
}

variable "zone" {
  default = "asia-southeast1-a" # Zone Singapore
}

variable "oslogin_username" {
  description = "OS Login POSIX username (from gcloud compute os-login describe-profile)"
}

variable "project_id" {
  description = "GCP project ID"
}

variable "vm_state" {
  description = "Desired state for all compute instances: RUNNING or TERMINATED"
  type        = string
  default     = "RUNNING"
}

