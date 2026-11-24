#!/usr/bin/env bash
# Runs on the Contabo server on every deploy. Safe to repeat:
# it only creates the Nginx site and certificate if they are missing,
# and never touches other sites (pms, cams, trippilot...).
set -euo pipefail

DOMAIN="porshi.tech"
ROOT="/var/www/porshi.tech"
CONF="/etc/nginx/sites-available/${DOMAIN}"

command -v nginx >/dev/null || { echo "Nginx is not installed on this server."; exit 1; }

# Stop if another enabled site already claims porshi.tech or www.porshi.tech
clash=$(grep -lE "server_name[^;]*[[:space:]](www\.)?porshi\.tech[[:space:];]" /etc/nginx/sites-enabled/* 2>/dev/null \
        | xargs -r readlink -f | grep -v "^$(readlink -f "$CONF" 2>/dev/null || echo none)$" || true)
if [ -n "$clash" ]; then
  echo "Another Nginx site already uses porshi.tech: $clash"
  echo "Remove porshi.tech from that file's server_name, then re-run this workflow."
  exit 1
fi

if [ ! -f "$CONF" ]; then
  echo "Creating Nginx site for ${DOMAIN}"
  cat > "$CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${ROOT};
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location = /index.html {
        add_header Cache-Control "no-cache";
        add_header X-Content-Type-Options nosniff always;
    }
}
EOF
  ln -sf "$CONF" "/etc/nginx/sites-enabled/${DOMAIN}"
fi

nginx -t
systemctl reload nginx

# HTTPS: only once, and only when DNS for both names already points here
if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
  me=$(curl -fsS4 https://api.ipify.org || true)
  a=$(getent ahostsv4 "${DOMAIN}" | awk 'NR==1{print $1}')
  w=$(getent ahostsv4 "www.${DOMAIN}" | awk 'NR==1{print $1}')
  if [ -z "${CERT_EMAIL:-}" ]; then
    echo "Skipping HTTPS: add the CERT_EMAIL secret in GitHub to enable it."
  elif [ "$a" != "$me" ] || [ "$w" != "$me" ]; then
    echo "Skipping HTTPS: DNS not ready (porshi.tech=$a, www=$w, this server=$me). Re-run once DNS points here."
  else
    command -v certbot >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx; }
    certbot --nginx --non-interactive --agree-tos --redirect -m "$CERT_EMAIL" -d "${DOMAIN}" -d "www.${DOMAIN}"
  fi
fi

echo "Deployed ${DOMAIN}"
