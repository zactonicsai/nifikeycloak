variable "aws_region" {
  description = "Which AWS data center region to use"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "YOUR laptop's public IP address, with /32 on the end (e.g. 203.0.113.25/32)"
  type        = string
}

variable "public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/tutorial-key.pub"
}

variable "keycloak_instance_type" {
  description = "Server size for Keycloak (needs about 2 GB of RAM)"
  type        = string
  default     = "t3.small"
}

variable "nifi_instance_type" {
  description = "Server size for NiFi (needs about 4 GB of RAM)"
  type        = string
  default     = "t3.medium"
}

variable "keycloak_admin_password" {
  description = "Bootstrap admin password for Keycloak"
  type        = string
  default     = "ChangeMeAdmin123!"
  sensitive   = true
}

variable "nifi_single_user_password" {
  description = "Temporary single-user password for NiFi (12+ chars, used before OIDC is enabled)"
  type        = string
  default     = "ChangeMeNifi12345!"
  sensitive   = true
}
