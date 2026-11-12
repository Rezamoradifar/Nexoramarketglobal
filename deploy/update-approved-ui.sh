#!/usr/bin/env bash
set -Eeuo pipefail
# Deploy only the approved Nexora React UI. No Nginx, DNS, SSL, wallet or contract mutations.
APP=/opt/nexora-markets
REPO=https://github.com/Rezamoradifar/Nexoramarketglobal.git
EXPECTED_HOST=nexoramarketglobal.live
EXPECTED_PREVIEW_PORT=3080
fail(){ printf 'NEXORA_UI_ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$EUID" -eq 0 ]] || fail 'Run as root on the Nexora VPS'
[[ -L "$APP/current" ]] || fail 'Current Nexora release symlink is missing; do not overwrite unrelated services'
for tool in git npm node curl nginx systemctl; do command -v "$tool" >/dev/null || fail "Missing $tool"; done

# Reuse the previously installed, isolated Node toolchain if present.
for bin in "$APP"/toolchain/node-v22.*-linux-*/bin; do
  [[ -x "$bin/node" ]] && [[ -x "$bin/npm" ]] && export PATH="$bin:$PATH" && break
done
nginx -t || fail 'Nginx config is invalid; leaving everything unchanged'
nginx -T 2>/dev/null | grep -Fq 'root /opt/nexora-markets/current/dist;' || fail 'Nginx does not point at Nexora release directory; refusing a potentially invisible deploy'
mkdir -p "$APP/releases"
STAMP="$(date -u +%Y%m%d%H%M%S)-$$"
RELEASE="$APP/releases/ui-$STAMP"
PREVIOUS="$(readlink "$APP/current")"
git clone --quiet --depth=1 --branch main "$REPO" "$RELEASE"
cd "$RELEASE"
grep -Fq 'Sustainable Investing in the Blockchain Era' src/App.jsx || fail 'Expected approved design is missing from source'
grep -Fq 'data:image/webp;base64' src/styles.css || fail 'Approved 3D coin image is missing from CSS'
if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
npm run build
[[ -s dist/index.html ]] || fail 'Production build missing index.html'

rollback(){
  code="$?"
  trap - ERR
  echo 'NEXORA_UI_ROLLBACK: restoring the previous React release' >&2
  ln -s "$PREVIOUS" "$APP/current.rollback"
  mv -Tf "$APP/current.rollback" "$APP/current"
  exit "$code"
}
trap rollback ERR
ln -s "$RELEASE" "$APP/current.next"
mv -Tf "$APP/current.next" "$APP/current"
nginx -t
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Compare the exact HTML bytes, so a default site or other React app cannot count as a success.
curl --fail --silent --show-error --max-time 15 "http://127.0.0.1:$EXPECTED_PREVIEW_PORT/" -o "$TMP"
if ! cmp -s "$TMP" "$RELEASE/dist/index.html"; then
  echo 'NEXORA_UI_ERROR: Port 3080 does not serve the newly built Nexora release' >&2
  false
fi
# Nginx may redirect HTTP to HTTPS; print domain status without changing any HTTPS config.
DOMAIN_CODE="$(curl -sS --max-time 8 -o /dev/null -w '%{http_code}' -H "Host: $EXPECTED_HOST" http://127.0.0.1/ || true)"
trap - ERR
trap - EXIT
rm -f "$TMP"
echo
echo 'NEXORA_APPROVED_3D_UI_DEPLOYED'
echo "Commit: $(git rev-parse --short HEAD)"
echo "Preview: http://103.244.227.112:$EXPECTED_PREVIEW_PORT/"
echo "Local apex domain HTTP response: $DOMAIN_CODE (200 or HTTPS redirect are both valid)"
echo 'Important: this script does NOT modify DNS, SSL certificates, Nginx routing or financial backend.'
