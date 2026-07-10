#!/bin/bash
# user-data for the KEYCLOAK server (runs automatically on first boot)
# Installs Docker, generates a self-signed HTTPS certificate with this
# server's public IP baked in, and starts Keycloak on HTTPS port 8443.
set -e
apt-get update -y
apt-get install -y docker.io docker-compose-v2 openssl
systemctl enable --now docker

# ---- 1. Generate the TLS certificate ----
CERT_DIR=/opt/keycloak/certs
mkdir -p $CERT_DIR

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout $CERT_DIR/keycloak.key \
  -out $CERT_DIR/keycloak.crt \
  -subj "/CN=keycloak" \
  -addext "subjectAltName=IP:$PUBLIC_IP"

chown 1000:1000 $CERT_DIR/keycloak.key $CERT_DIR/keycloak.crt
chmod 600 $CERT_DIR/keycloak.key
chmod 644 $CERT_DIR/keycloak.crt

# ---- 2. Start Keycloak over HTTPS ----
mkdir -p /opt/keycloak
cat > /opt/keycloak/docker-compose.yml <<'COMPOSE'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak
    command: start-dev
    restart: unless-stopped
    ports:
      - "8443:8443"
    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: ChangeMeAdmin123!
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/certs/keycloak.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/certs/keycloak.key
    volumes:
      - keycloak_data:/opt/keycloak/data
      - /opt/keycloak/certs:/opt/keycloak/certs:ro

volumes:
  keycloak_data:
COMPOSE

cd /opt/keycloak && docker compose up -d
