# ---------------------------------------------------------------
# Find the newest Ubuntu 24.04 image automatically.
# ---------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------
# Upload your public key so you can SSH in later.
# ---------------------------------------------------------------
resource "aws_key_pair" "tutorial" {
  key_name   = "tutorial-key"
  public_key = file(var.public_key_path)
}

# ---------------------------------------------------------------
# SERVER #1: KEYCLOAK (HTTPS)
# The user_data script installs Docker, generates a self-signed
# TLS certificate with this server's public IP baked into it,
# then starts Keycloak serving HTTPS on port 8443.
# (Same compose file as docker/keycloak/docker-compose.yml)
# ---------------------------------------------------------------
resource "aws_instance" "keycloak" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.keycloak_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.keycloak.id]
  key_name               = aws_key_pair.tutorial.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = <<-EOT
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y docker.io docker-compose-v2 openssl
    systemctl enable --now docker

    # ---- 1. Generate the TLS certificate ----
    # A certificate is a signed name tag. We bake this server's
    # PUBLIC IP into it (the subjectAltName) so browsers and NiFi
    # can check "the name tag matches the address I dialed."
    # We ask AWS's metadata service for the public IP.
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

    # The Keycloak container runs as user id 1000 - let it read them
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
          KC_BOOTSTRAP_ADMIN_PASSWORD: ${var.keycloak_admin_password}
          KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/certs/keycloak.crt
          KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/certs/keycloak.key
        volumes:
          - keycloak_data:/opt/keycloak/data
          - /opt/keycloak/certs:/opt/keycloak/certs:ro

    volumes:
      keycloak_data:
    COMPOSE

    cd /opt/keycloak && docker compose up -d
  EOT

  tags = { Name = "keycloak-server" }
}

# ---------------------------------------------------------------
# SERVER #2: NIFI
# Starts in single-user HTTPS mode; switch it to Keycloak login
# with scripts/configure-nifi-oidc.sh afterwards.
# (Same compose file as docker/nifi/docker-compose.yml)
# ---------------------------------------------------------------
resource "aws_instance" "nifi" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.nifi_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nifi.id]
  key_name               = aws_key_pair.tutorial.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = <<-EOT
    #!/bin/bash
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
          SINGLE_USER_CREDENTIALS_PASSWORD: ${var.nifi_single_user_password}
          NIFI_WEB_HTTPS_HOST: 0.0.0.0
          NIFI_WEB_PROXY_HOST: 0.0.0.0:8443
    COMPOSE

    cd /opt/nifi && docker compose up -d

    # LAB FIX: we connect to NiFi by raw IP, but NiFi 2.x rejects
    # requests whose TLS name (SNI) doesn't match its certificate
    # ("HTTP ERROR 400 Invalid SNI"). Wait for NiFi to write its
    # config file, relax the check, and restart once.
    P=/opt/nifi/nifi-current/conf/nifi.properties
    for i in $(seq 1 60); do
      if docker exec nifi test -s $P 2>/dev/null; then
        docker exec nifi bash -c "grep -q '^nifi.web.https.sni.host.check=' $P \
          && sed -i 's|^nifi.web.https.sni.host.check=.*|nifi.web.https.sni.host.check=false|' $P \
          || echo 'nifi.web.https.sni.host.check=false' >> $P"
        docker exec nifi bash -c "grep -q '^nifi.web.https.sni.required=' $P \
          && sed -i 's|^nifi.web.https.sni.required=.*|nifi.web.https.sni.required=false|' $P \
          || echo 'nifi.web.https.sni.required=false' >> $P"
        docker restart nifi
        break
      fi
      sleep 10
    done
  EOT

  tags = { Name = "nifi-server" }
}
