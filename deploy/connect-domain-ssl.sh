#!/usr/bin/env bash
set -Eeuo pipefail
# Finish Nexora's domain SSL after changing DNS at its provider.
# Never enables wallet/financial contracts.
DOMAIN="nexoramarketglobal.live"
WWW="www.nexoramarketglobal.live"
EXPECTED_IP="103.244.227.112"
NGINX_SITE="/etc/nginx/sites-enabled/nexora-domain-http"
NGINX_SOURCE="/etc/nginx/sites-available/nexora-domain-http"
fail() { echo "NEXORA_DOMAIN_ERROR: $*" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Run as root.'
for cmd in getent awk sort grep curl nginx apt-get; do command -v "$cmd" >/dev/null || fail "Missing $cmd"; done
[[ -L "$NGINX_SITE" ]] && [[ "$(readlink -f "$NGINX_SITE")" == "$NGINX_SOURCE" ]] || fail 'Domain Nginx site not configured; first run deploy/repair-live.sh'
[[ -f "$NGINX_SOURCE" ]] && grep -q 'Managed by Nexora Markets repair-live.sh' "$NGINX_SOURCE" || fail 'Unmanaged domain Nginx config; refusing to change'
nginx -t || fail 'Existing Nginx config invalid'
for host in "$DOMAIN" "$WWW"; do
  ipv4="$(getent ahostsv4 "$host" | awk '$1~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/{print $1}' | sort -u)"
  [[ -n "$ipv4" ]] || fail "$host has no A record yet. Set DNS, then rerun."
  if [[ "$ipv4" != "$EXPECTED_IP" ]]; then
    echo "Host $host currently resolves to:" >&2
    echo "$ipv4" >&2
    fail "Expected only $EXPECTED_IP; update DNS and wait before issuing SSL."
  fi
done
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
status="$(curl --silent --show-error --max-time 10 -o "$tmp" -w '%{http_code}' -H "Host: $DOMAIN" 'http://127.0.0.1/')" || fail 'Local HTTP port 80 not reachable'
[[ "$status" == 200 ]] && grep -Fq 'id="root"' "$tmp" || fail 'Domain HTTP route is not Nexora React; run repair-live.sh first'
backup="/opt/nexora-markets/backups/domain-before-ssl-$(date -u +%Y%m%d%H%M%S)"
mkdir -p "$backup"
cp -p "$NGINX_SOURCE" "$backup/nexora-domain-http.conf"
echo "NEXORA_DOMAIN_BACKUP: $backup"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y certbot python3-certbot-nginx >/dev/null
# Use supplied CERTBOT_EMAIL for renewal notifications; fallback allows no-email cert.
if [[ -n "$(printenv CERTBOT_EMAIL || true)" ]]; then
  certbot --nginx --non-interactive --agree-tos --no-eff-email --email "$CERTBOT_EMAIL" --redirect -d "$DOMAIN" -d "$WWW"
else
  certbot --nginx --non-interactive --agree-tos --no-eff-email --register-unsafely-without-email --redirect -d "$DOMAIN" -d "$WWW"
fi
nginx -t
systemctl reload nginx
status="$(curl --silent --show-error --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" -o "$tmp" -w '%{http_code}' "https://$DOMAIN/")" || fail 'HTTPS local verification failed'
[[ "$status" == 200 ]] && grep -Fq 'id="root"' "$tmp" || fail "HTTPS returned $status but Nexora React was not found"
echo 'NEXORA_DOMAIN_HTTPS_READY'
echo "https://$DOMAIN"
echo "https://$WWW"
echo 'Reminder: permit inbound TCP 80/443 in VPS provider firewall.'
