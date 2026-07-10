#!/bin/bash
# ================================================================
# fix-keycloak-https.sh
# ----------------------------------------------------------------
# LEGACY - only needed if you run Keycloak over plain HTTP.
# The project now runs Keycloak over HTTPS (port 8443) with real
# certificates, so this script is normally NOT needed anymore.
# Fixes the "We are sorry... HTTPS required" error.
#
# Why it happens: every Keycloak realm has a "Require SSL" setting
# that defaults to "external requests" - connections from the
# public internet must use HTTPS. Our lab runs plain HTTP on 8080,
# so Keycloak blocks your browser.
#
# This script sets sslRequired=NONE on the master realm, and on
# the nifi realm too if it exists. Run it ON THE KEYCLOAK SERVER:
#
#   ./fix-keycloak-https.sh [ADMIN_PASSWORD]
#
# Run it once right after the server boots (fixes the admin
# console), and again after you create the "nifi" realm - or just
# re-run it anytime; it's safe to repeat.
#
# WARNING - LAB ONLY: sslRequired=NONE means passwords travel
# unencrypted. Never do this in production; use a real TLS
# certificate and reverse proxy instead.
# ================================================================
set -euo pipefail

ADMIN_PASSWORD="${1:-ChangeMeAdmin123!}"
KCADM="/opt/keycloak/bin/kcadm.sh"

echo "==> Logging in to the Keycloak admin CLI..."
sudo docker exec keycloak $KCADM config credentials \
  --server http://localhost:8080 --realm master \
  --user admin --password "$ADMIN_PASSWORD"

echo "==> Allowing HTTP on the 'master' realm (fixes the admin console)..."
sudo docker exec keycloak $KCADM update realms/master -s sslRequired=NONE
echo "    Done."

echo "==> Checking for the 'nifi' realm..."
if sudo docker exec keycloak $KCADM get realms/nifi > /dev/null 2>&1; then
  sudo docker exec keycloak $KCADM update realms/nifi -s sslRequired=NONE
  echo "    'nifi' realm fixed too."
else
  echo "    'nifi' realm not created yet - re-run this script after you create it!"
fi

echo ""
echo "All set. Refresh your browser: http://<KEYCLOAK_IP>:8080"
