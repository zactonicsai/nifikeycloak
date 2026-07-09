#!/bin/bash
# user-data for the KEYCLOAK server (runs automatically on first boot)
set -e
apt-get update -y
apt-get install -y docker.io docker-compose-v2
systemctl enable --now docker

mkdir -p /opt/keycloak
cat > /opt/keycloak/docker-compose.yml <<'COMPOSE'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak
    command: start-dev
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: ChangeMeAdmin123!
    volumes:
      - keycloak_data:/opt/keycloak/data

volumes:
  keycloak_data:
COMPOSE

cd /opt/keycloak && docker compose up -d
