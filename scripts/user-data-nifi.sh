#!/bin/bash
# user-data for the NIFI server (runs automatically on first boot)
set -e
apt-get update -y
apt-get install -y docker.io docker-compose-v2
systemctl enable --now docker

mkdir -p /opt/nifi
cat > /opt/nifi/docker-compose.yml <<'COMPOSE'
services:
  nifi:
    image: apache/nifi:latest
    container_name: nifi
    restart: unless-stopped
    ports:
      - "8443:8443"
    environment:
      SINGLE_USER_CREDENTIALS_USERNAME: admin
      SINGLE_USER_CREDENTIALS_PASSWORD: ChangeMeNifi12345!
      NIFI_WEB_HTTPS_HOST: 0.0.0.0
      NIFI_WEB_PROXY_HOST: 0.0.0.0:8443
COMPOSE

cd /opt/nifi && docker compose up -d
