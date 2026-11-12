#!/usr/bin/env bash
set -Eeuo pipefail

# Restore original Nexora ChatGPT Sites version via safe 302 redirect.
# Preserve React releases and all other hosted domains, especially Moneyland.
DOMAIN="nexoramarketglobal.live"
WWW="www.nexoramarketglobal.live"
SITE="https://nexora-markets-preview.rezamoradifar.chatgpt.site"
EXPECTED_IP="103.244.227.112"
CONF="/etc/nginx/sites-available/nexora-domain-http"
ENABLED="/etc/nginx/sites-enabled/nexora-domain-http"

fail() { echo "NEXORA_RESTORE_ERROR: $*" >&2; exit 1; }
[[ "$EUID" -eq 0 ]] || fail "Run as root on Nexora VPS"
for cmd in nginx systemctl curl python3 getent awk grep; do
  command -v "$cmd" >/dev/null || fail "Missing command: $cmd"
done
[[ -f "$CONF" ]] || fail "Missing Nexora Nginx vhost: $CONF"
[[ -L "$ENABLED" && "$(readlink -f "$ENABLED")" == "$CONF" ]] ||
  fail "Nexora domain symlink not as expected; refusing to edit"
grep -q 'Managed by Nexora Markets repair-live.sh' "$CONF" ||
  fail "Domain config not Nexora-managed; refusing to edit"
nginx -t || fail "Existing Nginx config invalid"

for host in "$DOMAIN" "$WWW"; do
  actual="$(getent ahostsv4 "$host" | awk '{print $1}' | sort -u)"
  [[ "$actual" == "$EXPECTED_IP" ]] || fail "$host DNS=[$actual] instead of $EXPECTED_IP"
done

BACKUP="/opt/nexora-markets/backups/restore-original-sites-$(date -u +%Y%m%d%H%M%S)-$$"
mkdir -p "$BACKUP"
cp -p "$CONF" "$BACKUP/nexora-domain-http.conf"
echo "NEXORA_BACKUP: $BACKUP"

rollback() {
  code="$?"
  trap - ERR
  cp -p "$BACKUP/nexora-domain-http.conf" "$CONF"
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  echo "NEXORA_RESTORE_ROLLBACK: restored prior domain config (exit $code)" >&2
  exit "$code"
}
trap rollback ERR

python3 - "$CONF" "$SITE" <<'PY'
import pathlib, re, sys
p=pathlib.Path(sys.argv[1])
site=sys.argv[2].rstrip("/")
s=p.read_text()
pattern=r"location\s+/\s*\{\s*try_files\s+\$uri\s+\$uri/\s+/index\.html;\s*\}"
replacement=f"location / {{ return 302 {site}$request_uri; }}"
n=len(re.findall(pattern,s))
if not n:
    if replacement in s:
        print("NEXORA_RESTORE_ALREADY_CONFIGURED")
        sys.exit(0)
    raise SystemExit("NEXORA_RESTORE_ERROR: Unexpected location / block; no change made")
p.write_text(re.sub(pattern,lambda m: replacement,s))
print(f"NEXORA_RESTORE_LOCATION_UPDATED: {n}")
PY

nginx -t
systemctl reload nginx
loc="$(curl --silent --show-error --max-time 8 --output /dev/null --write-out '%{redirect_url}' -H "Host: $DOMAIN" http://127.0.0.1/)"
[[ "$loc" == "$SITE/" ]] || fail "Wrong redirect: [$loc]"
loc2="$(curl --silent --show-error --max-time 8 --output /dev/null --write-out '%{redirect_url}' -H "Host: $WWW" http://127.0.0.1/)"
[[ "$loc2" == "$SITE/" ]] || fail "Wrong www redirect: [$loc2]"
trap - ERR
echo "NEXORA_ORIGINAL_HTTP_RESTORED"
echo "HTTP http://$DOMAIN now sends visitors to $SITE/"

# Install and configure independent Nexora TLS; never replace Moneyland certificate.
if ! command -v certbot >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y certbot python3-certbot-nginx >/dev/null
fi
if [[ -n "$(printenv CERTBOT_EMAIL || true)" ]]; then
  if ! certbot --nginx --non-interactive --agree-tos --no-eff-email --no-redirect --email "$CERTBOT_EMAIL" -d "$DOMAIN" -d "$WWW"; then
    echo "NEXORA_HTTPS_PENDING: HTTP redirect works; Certbot failed." >&2
    exit 2
  fi
else
  if ! certbot --nginx --non-interactive --agree-tos --no-eff-email --no-redirect --register-unsafely-without-email -d "$DOMAIN" -d "$WWW"; then
    echo "NEXORA_HTTPS_PENDING: HTTP redirect works; Certbot failed." >&2
    exit 2
  fi
fi
nginx -t
systemctl reload nginx
https_loc="$(curl --silent --show-error --max-time 12 --resolve "$DOMAIN:443:127.0.0.1" --output /dev/null --write-out '%{redirect_url}' "https://$DOMAIN/")"
[[ "$https_loc" == "$SITE/" ]] || fail "HTTPS redirect did not match original site [$https_loc]"

echo "NEXORA_ORIGINAL_SITES_RESTORED"
echo "https://$DOMAIN -> $SITE/"
echo "https://$WWW -> $SITE/"
echo "Backup: $BACKUP"
echo "NOTICE: This is a redirect to the original ChatGPT Sites website, not a copy."
