#!/usr/bin/env bash
set -Eeuo pipefail

# Nexora Markets frontend-only deployment. Does not deploy a smart contract.
REPO_URL='https://github.com/Rezamoradifar/Nexoramarketglobal.git'
APP_ROOT='/opt/nexora-markets'
NGINX_NAME='nexora-markets-3080'
NGINX_CONF="/etc/nginx/sites-available/$NGINX_NAME"
NGINX_LINK="/etc/nginx/sites-enabled/$NGINX_NAME"
PORT=3080

if (( EUID != 0 )); then echo 'ERROR: run as root (sudo bash deploy-vps.sh)' >&2; exit 1; fi
if ! command -v apt-get >/dev/null; then echo 'ERROR: Ubuntu/Debian apt-get required' >&2; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx git curl ca-certificates xz-utils >/dev/null

# Use a pinned, checksum-verified Node runtime without replacing system Node.
NODE_VERSION='v22.16.0'
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH='x64';; aarch64) ARCH='arm64';; *) echo "ERROR: unsupported architecture $ARCH" >&2; exit 1;; esac
NODE_HOME="$APP_ROOT/toolchain/node-$NODE_VERSION-linux-$ARCH"
if [[ ! -x "$NODE_HOME/bin/node" ]]; then
  mkdir -p "$APP_ROOT/toolchain"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt"
  archive="node-$NODE_VERSION-linux-$ARCH.tar.xz"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/$archive" -o "$tmp/$archive"
  ( cd "$tmp"; grep " $archive\$" SHASUMS256.txt | sha256sum -c - )
  tar -xJf "$tmp/$archive" -C "$APP_ROOT/toolchain"
  rm -rf "$tmp"
  trap - EXIT
fi
export PATH="$NODE_HOME/bin:$PATH"

# Never overwrite an unrelated nginx listener on this port.
if [[ -f "$NGINX_CONF" ]] && ! grep -q 'Managed by Nexora Markets VPS deployment script' "$NGINX_CONF"; then
  echo "ERROR: existing $NGINX_CONF is not managed by Nexora; refusing to overwrite." >&2
  exit 1
fi
if [[ ! -e "$NGINX_CONF" ]]; then
  domain_conflict="$(grep -RlE 'server_name[^;]*nexoramarketglobal[.]live' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true)"
  if [[ -n "$domain_conflict" ]]; then
    echo "ERROR: domain already configured in: $domain_conflict" >&2
    exit 1
  fi
fi
if [[ ! -e "$NGINX_CONF" ]]; then
  conflicting="$(grep -RlE 'listen[[:space:]]+([^;]*:)?3080([[:space:];]|$)' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true)"
  if [[ -n "$conflicting" ]]; then
    echo "ERROR: port $PORT is already configured by: $conflicting" >&2
    echo 'Inspect that configuration before deploying; no nginx files were changed.' >&2
    exit 1
  fi
fi

stamp="$(date -u +%Y%m%d%H%M%S)"
release="$APP_ROOT/releases/$stamp"
mkdir -p "$APP_ROOT/releases"
git clone --quiet --depth 1 --branch main "$REPO_URL" "$release"
cd "$release"
if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
npm run build
[[ -s dist/index.html ]] || { echo 'ERROR: dist/index.html missing' >&2; exit 1; }

old_target=''
[[ ! -L "$APP_ROOT/current" ]] || old_target="$(readlink "$APP_ROOT/current")"
old_conf=''
if [[ -f "$NGINX_CONF" ]]; then
  old_conf="$APP_ROOT/nginx-$stamp.bak"
  cp -a "$NGINX_CONF" "$old_conf"
fi

rollback() {
  echo 'ERROR: deployment failed; restoring prior nginx config and release.' >&2
  if [[ -n "$old_target" ]]; then ln -sfn "$old_target" "$APP_ROOT/current"; else rm -f "$APP_ROOT/current"; fi
  if [[ -n "$old_conf" ]]; then cp -a "$old_conf" "$NGINX_CONF"; else rm -f "$NGINX_CONF" "$NGINX_LINK"; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
}
trap rollback ERR
ln -sfn "$release" "$APP_ROOT/current"
cat > "$NGINX_CONF" <<'NGINX'
# Managed by Nexora Markets VPS deployment script.
server {
    listen 3080;
    server_name 103.244.227.112 nexoramarketglobal.live www.nexoramarketglobal.live;
    root /opt/nexora-markets/current/dist;
    index index.html;
    autoindex off;
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    location / { try_files $uri $uri/ /index.html; }
    location ~ /\. { deny all; }
    location ~* \.(env|log|sql|bak|ini|conf)$ { deny all; }
}
server {
    listen 80;
    server_name nexoramarketglobal.live www.nexoramarketglobal.live;
    root /opt/nexora-markets/current/dist;
    index index.html;
    autoindex off;
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    location / { try_files $uri $uri/ /index.html; }
    location ~ /\. { deny all; }
    location ~* \.(env|log|sql|bak|ini|conf)$ { deny all; }
}
NGINX
ln -sfn "$NGINX_CONF" "$NGINX_LINK"
nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx
curl -fsS --max-time 10 -H 'Host: 103.244.227.112' "http://127.0.0.1:$PORT/" | grep -q '<div id="root"></div>'
trap - ERR
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow "$PORT/tcp" >/dev/null; fi
printf '\nNEXORA_DEPLOYED\nURL: http://103.244.227.112:%s\nCommit: %s\n' "$PORT" "$(git rev-parse --short HEAD)"
printf 'Note: HTTPS and DNS are separate; wallet and contract functions remain disabled.\n'