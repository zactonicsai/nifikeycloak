# Copy this file to terraform.tfvars and fill in your values.
# terraform.tfvars is read automatically, so you won't need -var flags.

my_ip           = "68.32.112.68/32" # <- YOUR IP from https://checkip.amazonaws.com (keep the /32)
public_key_path = "~/.ssh/tutorial-key.pub"
aws_region      = "us-east-1"

# Optional overrides:
keycloak_admin_password   = "keycloakpassword"
nifi_single_user_password = "nifipassword"
