# ---------------------------------------------------------------
# BOUNCER #1: Keycloak security group.
#   - Door 22 (SSH): only YOUR laptop
#   - Door 8443 (Keycloak HTTPS web + OIDC): open to all, because
#     both your browser AND the NiFi server must reach it.
#     Traffic is now encrypted, but still lock this down to known
#     IPs in production!
# ---------------------------------------------------------------
resource "aws_security_group" "keycloak" {
  name        = "keycloak-sg"
  description = "Rules for the Keycloak server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my laptop only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Keycloak HTTPS web + OIDC traffic"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "keycloak-sg" }
}

# ---------------------------------------------------------------
# BOUNCER #2: NiFi security group.
#   - Door 22 (SSH): only YOUR laptop
#   - Door 8443 (NiFi HTTPS UI): only YOUR laptop
# ---------------------------------------------------------------
resource "aws_security_group" "nifi" {
  name        = "nifi-sg"
  description = "Rules for the NiFi server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my laptop only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "NiFi HTTPS UI from my laptop only"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "nifi-sg" }
}
