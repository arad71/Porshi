#!/usr/bin/env bash
# Runs on the Contabo server on every deploy (as root). Safe to repeat.
#
# - Serves /var/www/porshi.tech from a small Nginx container ("porshi-site"),
#   reachable as 127.0.0.1:$SITE_PORT and, on the Docker network "porshi-site", as porshi-site:80.
# - Adds porshi.tech and www.porshi.tech to the server's existing Caddy, once.
#   Works whether Caddy is installed on the system or runs in a Docker container.
#   Other sites in the Caddyfile (pms, cams, motors...) are never changed: the block is only
#   appended, the config is validated, and the old file is restored if validation fails.
# - Caddy gets and renews the HTTPS certificate itself once DNS points at this server.
set -euo pipefail

DOMAIN="porshi.tech"
ROOT="/var/www/porshi.tech"
PORT="${SITE_PORT:-8090}"
NAME="porshi-site"
NET="porshi-site"
MARK="# porshi.tech website (managed by github.com/arad71/porshi - do not edit this line)"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker is not installed on this server."
mkdir -p "$ROOT"

# ---------------------------------------------------------------- 1. static site container
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker start "$NAME" >/dev/null
else
  if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q .; then
    die "Port $PORT is already in use. Add a SITE_PORT secret in GitHub with a free port (for example 8091) and re-run."
  fi
  say "Starting the $NAME container on 127.0.0.1:$PORT"
  docker run -d --name "$NAME" --restart unless-stopped \
    --network "$NET" --network-alias "$NAME" \
    -p "127.0.0.1:$PORT:80" \
    -v "$ROOT:/usr/share/nginx/html:ro" \
    --log-opt max-size=10m --log-opt max-file=3 \
    nginx:1.27-alpine >/dev/null
fi

for _ in 1 2 3 4 5; do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" && break
  sleep 1
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" || die "The site container is not answering on 127.0.0.1:$PORT."
say "Site files are being served on 127.0.0.1:$PORT"

# ---------------------------------------------------------------- 2. find Caddy
CT="$(docker ps --filter publish=443 --format '{{.Names}} {{.Image}}' | awk 'tolower($2) ~ /caddy/ {print $1; exit}')"
[ -n "$CT" ] || CT="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($2) ~ /caddy/ {print $1; exit}')"

if [ -n "$CT" ]; then
  say "Found Caddy in Docker container: $CT"
  CF="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{.Source}}{{end}}{{end}}' "$CT")"
  if [ -z "$CF" ]; then
    d="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy"}}{{.Source}}{{end}}{{end}}' "$CT")"
    [ -n "$d" ] && CF="$d/Caddyfile"
  fi
  [ -n "$CF" ] && [ -f "$CF" ] || die "Could not find the Caddyfile of container $CT on the host. Add this to it by hand:
porshi.tech { reverse_proxy $NAME:80 }   and run: docker network connect $NET $CT"
  docker network connect "$NET" "$CT" 2>/dev/null || true
  UPSTREAM="$NAME:80"
  validate() { docker exec "$CT" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; }
  reload()   { docker exec "$CT" caddy reload   --config /etc/caddy/Caddyfile --adapter caddyfile; }
elif systemctl is-active --quiet caddy 2>/dev/null; then
  say "Found Caddy installed on the system"
  CF="/etc/caddy/Caddyfile"
  [ -f "$CF" ] || die "Caddy is running but $CF does not exist."
  UPSTREAM="127.0.0.1:$PORT"
  validate() { caddy validate --config "$CF" --adapter caddyfile; }
  reload()   { systemctl reload caddy; }
else
  die "No running Caddy found (neither a Docker container nor the caddy service)."
fi
say "Caddyfile: $CF"

# ---------------------------------------------------------------- 3. add the site to Caddy (once)
if grep -qF "$MARK" "$CF"; then
  say "porshi.tech is already in the Caddyfile. Nothing to change."
else
  if grep -Eq '(^|[[:space:],])(https?://)?(www\.)?porshi\.tech(:[0-9]+)?([[:space:],{]|$)' "$CF"; then
    die "The Caddyfile already has a site for porshi.tech or www.porshi.tech that was not added by this deploy.
Remove or rename it in $CF, reload Caddy, then re-run this workflow."
  fi
  backup="$CF.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CF" "$backup"
  say "Backed up the Caddyfile to $backup"
  # append in place (same file), so a Caddyfile bind-mounted into a container sees the change
  cat >> "$CF" <<EOF

$MARK
$DOMAIN {
	encode zstd gzip
	reverse_proxy $UPSTREAM
}
www.$DOMAIN {
	redir https://$DOMAIN{uri} permanent
}
EOF
  if ! validate; then
    cat "$backup" > "$CF"
    die "Caddy rejected the new config, so the Caddyfile was put back exactly as it was. Nothing changed for your other sites."
  fi
  say "Added porshi.tech to the Caddyfile"
fi

reload
say "Caddy reloaded. Deployed $DOMAIN"
