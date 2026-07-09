#!/bin/bash
# ================================================================
# configure-nifi-oidc.sh
# ----------------------------------------------------------------
# Switches a running NiFi Docker container from single-user login
# to Keycloak (OIDC) login. Run this ON THE NIFI EC2 SERVER after:
#   1. Creating the "nifi" realm in Keycloak
#   2. Creating the "nifi" client (Client authentication: ON)
#   3. Adding the redirect + logout URIs to that client
#   4. Creating users (alice@example.com will be NiFi's admin)
#
# Usage:
#   ./configure-nifi-oidc.sh <KEYCLOAK_IP> <CLIENT_SECRET> [ADMIN_EMAIL]
#
# Example:
#   ./configure-nifi-oidc.sh 54.12.34.56 AbCdEf123... alice@example.com
# ================================================================
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <KEYCLOAK_IP> <CLIENT_SECRET> [ADMIN_EMAIL]"
  exit 1
fi

KEYCLOAK_IP="$1"
CLIENT_SECRET="$2"
ADMIN_EMAIL="${3:-alice@example.com}"

P=/opt/nifi/nifi-current/conf/nifi.properties
A=/opt/nifi/nifi-current/conf/authorizers.xml
DISCOVERY="http://${KEYCLOAK_IP}:8080/realms/nifi/.well-known/openid-configuration"

echo "==> Checking that Keycloak's discovery URL is reachable..."
curl -sf "$DISCOVERY" > /dev/null || {
  echo "ERROR: Cannot reach $DISCOVERY"
  echo "  - Is the 'nifi' realm created?"
  echo "  - Does the Keycloak security group allow port 8080?"
  exit 1
}
echo "    OK!"

echo "==> Updating nifi.properties inside the container..."
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.discovery.url=.*|nifi.security.user.oidc.discovery.url=${DISCOVERY}|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.client.id=.*|nifi.security.user.oidc.client.id=nifi|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.client.secret=.*|nifi.security.user.oidc.client.secret=${CLIENT_SECRET}|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.claim.identifying.user=.*|nifi.security.user.oidc.claim.identifying.user=email|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.additional.scopes=.*|nifi.security.user.oidc.additional.scopes=profile,email|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.login.identity.provider=.*|nifi.security.user.login.identity.provider=|" $P
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.authorizer=.*|nifi.security.user.authorizer=managed-authorizer|" $P

echo "==> Setting ${ADMIN_EMAIL} as the Initial Admin in authorizers.xml..."
sudo docker exec nifi sed -i \
  "s|<property name=\"Initial Admin Identity\">.*</property>|<property name=\"Initial Admin Identity\">${ADMIN_EMAIL}</property>|g" $A
sudo docker exec nifi sed -i \
  "s|<property name=\"Initial User Identity 1\">.*</property>|<property name=\"Initial User Identity 1\">${ADMIN_EMAIL}</property>|g" $A

echo "==> Clearing any old user/permission files so the Initial Admin is applied..."
sudo docker exec nifi bash -c \
  "rm -f /opt/nifi/nifi-current/conf/users.xml /opt/nifi/nifi-current/conf/authorizations.xml" || true

echo "==> Restarting NiFi (takes 2-3 minutes to come back)..."
sudo docker restart nifi

echo ""
echo "Done! In a fresh incognito window, open https://<NIFI_IP>:8443/nifi"
echo "You should be redirected to Keycloak. Log in as ${ADMIN_EMAIL}."
echo "Watch startup progress with:  sudo docker logs -f nifi"
