#!/usr/bin/env bash
# Nexora read-only health diagnosis. Never changes configuration or services.
set -u
DOMAIN=nexoramarketglobal.live
IP=103.244.227.112
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
section(){ printf '\n=== %s ===\n' "$1"; }
section "TIME AND HOST"
date -u '+UTC: %Y-%m-%dT%H:%M:%SZ'
hostname || true
section "DNS VIA SERVER RESOLVER"
for host in "$DOMAIN" "www.$DOMAIN"; do
  echo "Host: $host"
  getent ahostsv4 "$host" 2>&1 | awk '!seen[$1]++ && NR<=12 {print $1}' || true
done
section "LISTENING PORTS"
ss -lntp 2>&1 | grep -E ':(80|443|3080)([[:space:]]|$)' || true
section "NGINX CONFIGURATION TEST"
nginx -t 2>&1 || true
section "NEXORA ROUTING CONFIG SUMMARY"
for file in /etc/nginx/sites-enabled/nexora-3080 /etc/nginx/sites-enabled/nexora-domain-http; do
  echo "File: $file"
  if [[ -f "$file" ]]; then
    ls -l "$file"
    grep -nE '^[[:space:]]*(listen|server_name|root|proxy_pass|try_files)[[:space:]]' "$file" || true
  else
    echo "MISSING"
  fi
done
section "RELEASE"
if [[ -L /opt/nexora-markets/current ]]; then
  readlink -f /opt/nexora-markets/current || true
  find -L /opt/nexora-markets/current/dist -maxdepth 1 -type f -name index.html -printf 'React index exists: %p\n' 2>/dev/null || true
else
  echo "No current release symlink"
fi
check() {
  local label="$1" url="$2"; shift 2
  local file="$TMP/$label.html" status
  status="$(curl --silent --show-error --connect-timeout 4 --max-time 10 --output "$file" --write-out '%{http_code}' "$@" "$url" 2>"$TMP/$label.err")" || status="ERR"
  printf '%s: HTTP=%s' "$label" "$status"
  if [[ -s "$file" ]] && grep -Fq 'id="root"' "$file"; then
    printf ' ReactRoot=YES'
  else
    printf ' ReactRoot=NO'
  fi
  if [[ -s "$file" ]] && grep -iq 'welcome to nginx' "$file"; then
    printf ' NginxWelcome=YES'
  fi
  printf '\n'
  if [[ -s "$TMP/$label.err" ]]; then
    head -c 220 "$TMP/$label.err"; printf '\n'
  fi
}
section "LOCAL HTTP CHECKS"
check local3080 'http://127.0.0.1:3080/'
check domain80 'http://127.0.0.1/' -H "Host: $DOMAIN"
check www80 'http://127.0.0.1/' -H "Host: www.$DOMAIN"
section "LOCAL HTTPS CHECK (VALIDATION ENABLED)"
check domain443 "https://$DOMAIN/" --resolve "$DOMAIN:443:127.0.0.1"
section "PUBLIC DOMAIN CHECK"
check public_http "http://$DOMAIN/"
check public_https "https://$DOMAIN/"
section "CERTIFICATE STATUS"
if command -v certbot >/dev/null 2>&1; then
  timeout 15 certbot certificates 2>&1 | sed -n '1,35p' || true
else
  echo "certbot not installed"
fi
section "NGINX ERRORS (LAST 12)"
if [[ -r /var/log/nginx/error.log ]]; then tail -n 12 /var/log/nginx/error.log || true; else echo "Not readable"; fi
section "END (READ-ONLY)"
