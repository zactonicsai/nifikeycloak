output "keycloak_public_ip" {
  description = "Public IP of the Keycloak server"
  value       = aws_instance.keycloak.public_ip
}

output "keycloak_url" {
  description = "Open this in your browser (expect a certificate warning - self-signed)"
  value       = "https://${aws_instance.keycloak.public_ip}:8443"
}

output "oidc_discovery_url" {
  description = "The URL NiFi uses to find Keycloak (after you create the nifi realm)"
  value       = "https://${aws_instance.keycloak.public_ip}:8443/realms/nifi/.well-known/openid-configuration"
}

output "nifi_public_ip" {
  description = "Public IP of the NiFi server"
  value       = aws_instance.nifi.public_ip
}

output "nifi_url" {
  description = "Open this in your browser (expect a certificate warning)"
  value       = "https://${aws_instance.nifi.public_ip}:8443/nifi"
}

output "nifi_redirect_uri" {
  description = "Paste this into the Keycloak client's Valid redirect URIs"
  value       = "https://${aws_instance.nifi.public_ip}:8443/nifi-api/access/oidc/callback"
}

output "nifi_logout_uri" {
  description = "Paste this into the Keycloak client's Valid post logout redirect URIs"
  value       = "https://${aws_instance.nifi.public_ip}:8443/nifi-api/access/oidc/logout/callback"
}

output "ssh_keycloak" {
  value = "ssh -i ~/.ssh/tutorial-key ubuntu@${aws_instance.keycloak.public_ip}"
}

output "ssh_nifi" {
  value = "ssh -i ~/.ssh/tutorial-key ubuntu@${aws_instance.nifi.public_ip}"
}

output "ssm_keycloak" {
  description = "Keyless terminal via SSM (needs the Session Manager plugin, or use the AWS Console)"
  value       = "aws ssm start-session --target ${aws_instance.keycloak.id}"
}

output "ssm_nifi" {
  description = "Keyless terminal via SSM (needs the Session Manager plugin, or use the AWS Console)"
  value       = "aws ssm start-session --target ${aws_instance.nifi.id}"
}
