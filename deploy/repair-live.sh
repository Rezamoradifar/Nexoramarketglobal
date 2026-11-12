#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy ONLY Nexora's public, frontend-only React site.
# Keeps the existing default Nginx site and other applications untouched.
REPO="https://github.com/Rezamoradifar/Nexoramarketglobal.git"
APP="/opt/nexora-markets"
PREVIEW_ENABLED="/etc/nginx/sites-enabled/nexora-3080"
DOMAIN_AVAILABLE="/etc/nginx/sites-available/nexora-domain-http"
DOMAIN_ENABLED="/etc/nginx/sites-enabled/nexora-domain-http"

die() { echo "NEXORA_ERROR: $*" >&2; exit 1; }
[[ "$EUID" -eq 0 ]] || die "Run as root."
for cmd in nginx systemctl git curl grep; do command -v "$cmd" >/dev/null || die "$cmd is required"; done
nginx -t || die "Existing Nginx configuration is not valid"
[[ -f "$PREVIEW_ENABLED" ]] || die "Existing /etc/nginx/sites-enabled/nexora-3080 not found"
PREVIEW_REAL="$(readlink -f "$PREVIEW_ENABLED")"
case "$PREVIEW_REAL" in
  /etc/nginx/sites-available/*|/etc/nginx/sites-enabled/nexora-3080) ;;
  *) die "Unexpected Nexora Nginx config target: $PREVIEW_REAL" ;;
esac
grep -Eq 'listen[[:space:]]+[^;]*3080' "$PREVIEW_REAL" || die "The existing Nexora config does not listen on port 3080"
if [[ -e "$APP/current" && ! -L "$APP/current" ]]; then die "$APP/current is not a symlink; refusing to replace"; fi
if [[ -e "$DOMAIN_AVAILABLE" ]] && ! grep -q 'Managed by Nexora Markets repair-live.sh' "$DOMAIN_AVAILABLE"; then
  die "$DOMAIN_AVAILABLE is not managed by this script"
fi
if [[ -e "$DOMAIN_ENABLED" && ! -L "$DOMAIN_ENABLED" ]]; then
  die "$DOMAIN_ENABLED exists and is not a symlink"
fi
if [[ -L "$DOMAIN_ENABLED" && "$(readlink -f "$DOMAIN_ENABLED")" != "$DOMAIN_AVAILABLE" ]]; then
  die "Existing Nexora domain symlink points elsewhere"
fi
# Avoid clobbering any other port-3080 or Nexora-domain vhost.
for conf in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
  [[ -f "$conf" ]] || continue
  [[ "$(readlink -f "$conf")" == "$PREVIEW_REAL" ]] && continue
  [[ "$(readlink -f "$conf")" == "$DOMAIN_AVAILABLE" ]] && continue
  if grep -Eq 'listen[[:space:]]+[^;]*3080' "$conf"; then
    die "Another Nginx config uses port 3080: $conf"
  fi
  if grep -Eq 'server_name[[:space:]][^;]*nexoramarketglobal[.]live' "$conf"; then
    die "Another Nginx config owns the domain: $conf"
  fi
done

# Reuse the pinned Node 22 toolchain installed by the earlier Nexora installer.
for bin in "$APP"/toolchain/node-v22.*-linux-*/bin; do
  if [[ -x "$bin/node" && -x "$bin/npm" ]]; then export PATH="$bin:$PATH"; break; fi
done
command -v node >/dev/null && command -v npm >/dev/null || die "Node.js/npm missing. Run the original installer until the Node toolchain is installed."
node -e 'const [a,b]=process.versions.node.split(".").map(Number); if(!(a>22||(a===22&&b>=12)||(a===20&&b>=19)))process.exit(1)' || die "Node version is too old for Vite 7"
mkdir -p "$APP/releases" "$APP/backups"
STAMP="$(date -u +%Y%m%d%H%M%S)-$$"
RELEASE="$APP/releases/$STAMP"
git clone --quiet --depth 1 --branch main "$REPO" "$RELEASE"
cd "$RELEASE"
if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
npm run build
[[ -s dist/index.html ]] && grep -q 'id="root"' dist/index.html || die "React build output is incomplete"

# Back up existing Nexora Nginx configuration before touching it.
BACKUP="$APP/backups/$STAMP"
mkdir -p "$BACKUP"
cp -p "$PREVIEW_REAL" "$BACKUP/preview.conf"
DOMAIN_HAD_FILE=0
if [[ -f "$DOMAIN_AVAILABLE" ]]; then
  DOMAIN_HAD_FILE=1
  cp -p "$DOMAIN_AVAILABLE" "$BACKUP/domain.conf"
fi
DOMAIN_HAD_LINK=0
[[ -L "$DOMAIN_ENABLED" ]] && DOMAIN_HAD_LINK=1
OLD_RELEASE=""
[[ -L "$APP/current" ]] && OLD_RELEASE="$(readlink "$APP/current")"

rollback() {
  code=$?
  trap - ERR
  echo "NEXORA_ROLLBACK: restoring the previous routing (exit code $code)" >&2
  cp -p "$BACKUP/preview.conf" "$PREVIEW_REAL"
  if [[ "$DOMAIN_HAD_FILE" -eq 1 ]]; then
    cp -p "$BACKUP/domain.conf" "$DOMAIN_AVAILABLE"
  else
    rm -f "$DOMAIN_AVAILABLE"
  fi
  if [[ "$DOMAIN_HAD_LINK" -eq 0 ]]; then rm -f "$DOMAIN_ENABLED"; fi
  if [[ -n "$OLD_RELEASE" ]]; then ln -sfnT "$OLD_RELEASE" "$APP/current"; else rm -f "$APP/current"; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  exit "$code"
}
trap rollback ERR

ln -sfnT "$RELEASE" "$APP/current"

cat > "$PREVIEW_REAL" <<'NGINX'
# Managed by Nexora Markets repair-live.sh
server {
    listen 3080;
    server_name _;
    root /opt/nexora-markets/current/dist;
    index index.html;
    autoindex off;
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    location / { try_files $uri $uri/ /index.html; }
    location ~ /\.(?!well-known) { deny all; }
    location ~* \.(env|log|sql|bak|ini|conf)$ { deny all; }
}
NGINX
cat > "$DOMAIN_AVAILABLE" <<'NGINX'
# Managed by Nexora Markets repair-live.sh
server {
    listen 80;
    server_name nexoramarketglobal.live www.nexoramarketglobal.live;
    root /opt/nexora-markets/current/dist;
    index index.html;
    autoindex off;
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    location / { try_files $uri $uri/ /index.html; }
    location ~ /\.(?!well-known) { deny all; }
    location ~* \.(env|log|sql|bak|ini|conf)$ { deny all; }
}
NGINX
ln -sfn "$DOMAIN_AVAILABLE" "$DOMAIN_ENABLED"

nginx -t
systemctl reload nginx

# Nginx reload is asynchronous; retry while new workers pick up the config.
# Read into a file: curl | grep -q under pipefail can fail with SIGPIPE even on HTTP 200.
check_http() {
  local label="$1" url="$2" host="${3:-}"
  local out="$BACKUP/health-${label}.html"
  local code="000" attempt
  local -a curl_args=(--silent --show-error --max-time 8 --output "$out" --write-out '%{http_code}')
  [[ -z "$host" ]] || curl_args+=(-H "Host: $host")
  for attempt in {1..12}; do
    code="$(curl "${curl_args[@]}" "$url")" || code="CURL_ERROR"
    if [[ "$code" == "200" ]] && grep -Fq 'id="root"' "$out"; then
      echo "NEXORA_HTTP_CHECK_OK ${label}: 200 / React root found (attempt ${attempt})"
      return 0
    fi
    echo "NEXORA_HTTP_CHECK_RETRY ${label}: HTTP ${code} (attempt ${attempt}/12)"
    sleep 1
  done
  echo "NEXORA_HTTP_CHECK_FAILED ${label}: ${url} HTTP ${code}" >&2
  if [[ -f "$out" ]]; then
    echo "NEXORA_HTTP_RESPONSE_SAMPLE (${out}):" >&2
    head -c 400 "$out" >&2 || true
    printf '\\n' >&2
  fi
  echo "NEXORA_NGINX_ERRORS:" >&2
  tail -n 12 /var/log/nginx/error.log >&2 || true
  return 1
}
check_http preview 'http://127.0.0.1:3080/'
check_http domain 'http://127.0.0.1/' 'nexoramarketglobal.live'
trap - ERR

printf '\nNEXORA_HTTP_READY\n'
printf 'Commit: %s\n' "$(git rev-parse --short HEAD)"
printf 'Port 3080: http://103.244.227.112:3080/\n'
printf 'Local domain route: HTTP 200 with React shell\n'
printf 'Domain HTTP: http://nexoramarketglobal.live/ (requires A record to 103.244.227.112)\n'
printf 'Nginx backup: %s\n' "$BACKUP"
printf 'NOTICE: HTTPS/SSL and BNB smart-contract deployment are NOT part of this script.\n'
