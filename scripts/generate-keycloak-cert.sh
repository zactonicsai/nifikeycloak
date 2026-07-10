#!/bin/bash
# ================================================================
# generate-keycloak-cert.sh
# ----------------------------------------------------------------
# Creates (or re-creates) a self-signed TLS certificate for
# Keycloak and restarts the container so it takes effect.
# Run ON THE KEYCLOAK SERVER:
#
#   ./generate-keycloak-cert.sh
#
# The Terraform build already runs these exact steps at first
# boot, so you only need this script if:
#   - the server was stopped/started and got a NEW public IP
#     (the old cert has the old IP baked in -> regenerate!)
#   - the cert expired (it lasts 365 days)
#   - you built the server manually without the user-data script
#
# How the cert works, in plain language:
#   A certificate is like a signed name tag: "I am 54.12.34.56,
#   and here is a tamper-proof stamp proving it." Browsers and
#   NiFi check the name tag against the address they dialed.
#   That's why we bake the server's PUBLIC IP into the cert
#   (the "subjectAltName") - a cert for the wrong name is
#   rejected even if the stamp is valid.
#
#   Self-signed means WE stamped it ourselves instead of paying a
#   trusted authority. The encryption is just as strong, but
#   nobody trusts our stamp by default - so browsers show a
#   warning, and NiFi needs the cert added to its TRUSTSTORE
#   (its personal list of stamps it trusts). That import happens
#   in configure-nifi-oidc.sh on the NiFi server.
# ================================================================
set -euo pipefail

CERT_DIR=/opt/keycloak/certs
sudo mkdir -p $CERT_DIR

# Ask AWS's metadata service (a special address only the server
# itself can reach) for this machine's public IP.
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

echo "==> Generating certificate for IP: $PUBLIC_IP"
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout $CERT_DIR/keycloak.key \
  -out $CERT_DIR/keycloak.crt \
  -subj "/CN=keycloak" \
  -addext "subjectAltName=IP:$PUBLIC_IP"

# The Keycloak container runs as user id 1000 - let it read the files.
sudo chown 1000:1000 $CERT_DIR/keycloak.key $CERT_DIR/keycloak.crt
sudo chmod 600 $CERT_DIR/keycloak.key
sudo chmod 644 $CERT_DIR/keycloak.crt

echo "==> Restarting Keycloak to load the new certificate..."
cd /opt/keycloak && sudo docker compose up -d --force-recreate

echo ""
echo "Done! Keycloak is now serving HTTPS at: https://$PUBLIC_IP:8443"
echo ""
echo "IMPORTANT: if you regenerated this cert, NiFi's truststore has"
echo "the OLD one. Re-run configure-nifi-oidc.sh on the NiFi server."
