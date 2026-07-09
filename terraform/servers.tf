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
# SERVER #1: KEYCLOAK
# The user_data script installs Docker + the Compose plugin,
# writes the docker-compose.yml, and starts Keycloak.
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
          KC_BOOTSTRAP_ADMIN_PASSWORD: ${var.keycloak_admin_password}
        volumes:
          - keycloak_data:/opt/keycloak/data

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
  EOT

  tags = { Name = "nifi-server" }
}
