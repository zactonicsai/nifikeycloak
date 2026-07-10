#!/bin/bash
# ================================================================
# configure-nifi-oidc.sh  (HTTPS edition)
# ----------------------------------------------------------------
# Switches a running NiFi Docker container from single-user login
# to Keycloak (OIDC) login over HTTPS. It also handles the trust
# problem: Keycloak's certificate is self-signed, so NiFi won't
# trust it until we add it to NiFi's TRUSTSTORE - NiFi's personal
# address book of certificates it believes.
#
# What this script does, in order:
#   1. Downloads Keycloak's certificate straight from port 8443
#   2. Imports it into NiFi's truststore (conf/truststore.p12)
#   3. Tells NiFi to use its own truststore for OIDC calls
#   4. Points NiFi at Keycloak's HTTPS discovery URL
#   5. Sets client id/secret, identity claim, scopes
#   6. Disables single-user login, enables the managed authorizer
#   7. Sets the Initial Admin and restarts NiFi
#
# Run this ON THE NIFI EC2 SERVER after:
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
#
# Re-run it any time (e.g. after regenerating Keycloak's cert) -
# every step is safe to repeat.
# ================================================================
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <KEYCLOAK_IP> <CLIENT_SECRET> [ADMIN_EMAIL]"
  exit 1
fi

KEYCLOAK_IP="$1"
CLIENT_SECRET="$2"
ADMIN_EMAIL="${3:-alice@example.com}"

NIFI_CONF=/opt/nifi/nifi-current/conf
P=$NIFI_CONF/nifi.properties
A=$NIFI_CONF/authorizers.xml
DISCOVERY="https://${KEYCLOAK_IP}:8443/realms/nifi/.well-known/openid-configuration"

echo "==> Checking that Keycloak's discovery URL is reachable..."
# -k skips cert verification for THIS check only (we haven't imported
# the cert yet - that's literally the next step)
curl -skf "$DISCOVERY" > /dev/null || {
  echo "ERROR: Cannot reach $DISCOVERY"
  echo "  - Is the 'nifi' realm created in Keycloak?"
  echo "  - Does the Keycloak security group allow port 8443?"
  echo "  - Is Keycloak running? (sudo docker ps on the Keycloak server)"
  exit 1
}
echo "    OK!"

echo "==> Step 1: Downloading Keycloak's certificate from ${KEYCLOAK_IP}:8443..."
openssl s_client -connect "${KEYCLOAK_IP}:8443" -servername keycloak </dev/null 2>/dev/null \
  | openssl x509 > /tmp/keycloak.crt
echo "    Got it:"
openssl x509 -in /tmp/keycloak.crt -noout -subject -ext subjectAltName | sed 's/^/      /'

echo "==> Step 2: Importing it into NiFi's truststore..."
# NiFi auto-generated its truststore at startup; the password lives
# in nifi.properties. Read it out:
TRUST_PASS=$(sudo docker exec nifi grep '^nifi.security.truststorePasswd=' $P | cut -d= -f2)
if [ -z "$TRUST_PASS" ]; then
  echo "ERROR: could not read the truststore password from nifi.properties"
  exit 1
fi

sudo docker cp /tmp/keycloak.crt nifi:/tmp/keycloak.crt

# Remove any previous import (so re-running after a cert change works),
# then import the fresh cert under the alias "keycloak".
sudo docker exec nifi keytool -delete -alias keycloak \
  -keystore $NIFI_CONF/truststore.p12 -storetype PKCS12 \
  -storepass "$TRUST_PASS" 2>/dev/null || true

sudo docker exec nifi keytool -importcert -noprompt -alias keycloak \
  -file /tmp/keycloak.crt \
  -keystore $NIFI_CONF/truststore.p12 -storetype PKCS12 \
  -storepass "$TRUST_PASS"
echo "    Imported (alias: keycloak)."

echo "==> Step 3: Telling NiFi to use its own truststore for OIDC..."
sudo docker exec nifi sed -i \
  "s|^nifi.security.user.oidc.truststore.strategy=.*|nifi.security.user.oidc.truststore.strategy=NIFI|" $P

echo "==> Steps 4-6: Updating nifi.properties for Keycloak login..."
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

echo "==> Step 7: Setting ${ADMIN_EMAIL} as the Initial Admin..."
sudo docker exec nifi sed -i \
  "s|<property name=\"Initial Admin Identity\">.*</property>|<property name=\"Initial Admin Identity\">${ADMIN_EMAIL}</property>|g" $A
sudo docker exec nifi sed -i \
  "s|<property name=\"Initial User Identity 1\">.*</property>|<property name=\"Initial User Identity 1\">${ADMIN_EMAIL}</property>|g" $A

echo "==> Clearing old user/permission files so the Initial Admin is applied..."
sudo docker exec nifi bash -c \
  "rm -f $NIFI_CONF/users.xml $NIFI_CONF/authorizations.xml" || true

echo "==> Restarting NiFi (takes 2-3 minutes to come back)..."
sudo docker restart nifi

echo ""
echo "Done! In a fresh incognito window, open https://<NIFI_IP>:8443/nifi"
echo "You should be redirected to Keycloak (accept ITS cert warning too)."
echo "Log in as ${ADMIN_EMAIL}."
echo "Watch startup progress with:  sudo docker logs -f nifi"
