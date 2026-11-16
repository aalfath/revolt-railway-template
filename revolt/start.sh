#!/bin/bash
# Start script for the Revolt (Stoat) all-in-one Railway service.
# Writes Revolt.toml from the service variables, derives the instance keys from
# REVOLT_SECRET, injects the public URL into the web client, then runs the
# backend processes and Caddy. If any process exits, the container exits and
# Railway restarts it.
set -euo pipefail

die() { echo "[revolt] ERROR: $*" >&2; exit 1; }
log() { echo "[revolt] $*"; }
# Escape a value for a TOML basic string.
q() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

export PORT="${PORT:-8080}"

# ---- Public URL ------------------------------------------------------------
if [ -n "${REVOLT_PUBLIC_URL:-}" ]; then
  PUBLIC_URL="${REVOLT_PUBLIC_URL%/}"
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
else
  die "No public URL. Generate a Railway domain for this service or set REVOLT_PUBLIC_URL."
fi
export REVOLT_PUBLIC_URL="$PUBLIC_URL"
HOST_ONLY="${PUBLIC_URL#*://}"; HOST_ONLY="${HOST_ONLY%%/*}"
case "$PUBLIC_URL" in https://*) WS_URL="wss://${PUBLIC_URL#https://}" ;; *) WS_URL="ws://${PUBLIC_URL#http://}" ;; esac

# ---- Required connections ---------------------------------------------------
: "${MONGODB_URL:?MONGODB_URL is required (reference your MongoDB service)}"
: "${REDIS_URL:?REDIS_URL is required (reference your Redis service)}"
: "${RABBITMQ_HOST:?RABBITMQ_HOST is required (reference your RabbitMQ service)}"
: "${RABBITMQ_USER:?RABBITMQ_USER is required}"
: "${RABBITMQ_PASSWORD:?RABBITMQ_PASSWORD is required}"
: "${S3_ENDPOINT:?S3_ENDPOINT is required (reference your bucket)}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"
: "${REVOLT_SECRET:?REVOLT_SECRET is required (a long random string)}"
[ "${#REVOLT_SECRET}" -ge 32 ] || die "REVOLT_SECRET must be at least 32 characters."
S3_REGION="${S3_REGION:-auto}"
S3_PATH_STYLE="${S3_PATH_STYLE:-true}"
INVITE_ONLY="${REVOLT_INVITE_ONLY:-false}"

# ---- Keys derived from REVOLT_SECRET (stable across redeploys) -------------
# File encryption key: 32 bytes, base64.
FILES_KEY=$(printf '%s' "files:${REVOLT_SECRET}" | openssl dgst -sha256 -binary | base64)
# Web Push (VAPID) P-256 key pair, from a scalar derived from the secret.
TMPK=$(mktemp -d)
SCALAR=$(printf '%s' "vapid:${REVOLT_SECRET}" | openssl dgst -sha256 -binary | xxd -p -c 64)
printf '30310201010420%sa00a06082a8648ce3d030107' "$SCALAR" | xxd -r -p > "$TMPK/k.der"
openssl ec -inform DER -in "$TMPK/k.der" -out "$TMPK/k.pem" 2>/dev/null || die "could not derive the VAPID key"
VAPID_PRIVATE=$(base64 -w0 "$TMPK/k.pem" | tr -d '=')
VAPID_PUBLIC=$(openssl ec -in "$TMPK/k.pem" -outform DER 2>/dev/null | tail -c 65 | base64 -w0 | tr '/+' '_-' | tr -d '=')
rm -rf "$TMPK"

# ---- Revolt.toml -------------------------------------------------------------
mkdir -p /opt/revolt/run
cat > /opt/revolt/run/Revolt.toml <<TOML
production = true
environment = "production"

[database]
mongodb = $(q "$MONGODB_URL")
redis = $(q "$REDIS_URL")

[hosts]
app = $(q "$PUBLIC_URL")
api = $(q "$PUBLIC_URL/api")
events = $(q "$WS_URL/ws")
autumn = $(q "$PUBLIC_URL/autumn")
january = $(q "$PUBLIC_URL/january")

[rabbit]
host = $(q "$RABBITMQ_HOST")
port = ${RABBITMQ_PORT:-5672}
username = $(q "$RABBITMQ_USER")
password = $(q "$RABBITMQ_PASSWORD")

[api.registration]
invite_only = ${INVITE_ONLY}

[pushd.vapid]
private_key = $(q "$VAPID_PRIVATE")
public_key = $(q "$VAPID_PUBLIC")

[files]
encryption_key = $(q "$FILES_KEY")

[files.s3]
endpoint = $(q "$S3_ENDPOINT")
path_style_buckets = ${S3_PATH_STYLE}
region = $(q "$S3_REGION")
access_key_id = $(q "$S3_ACCESS_KEY_ID")
secret_access_key = $(q "$S3_SECRET_ACCESS_KEY")
default_bucket = $(q "$S3_BUCKET")
TOML
chmod 600 /opt/revolt/run/Revolt.toml

# ---- Web client: inject the public URLs (same as the upstream inject.js) ----
rm -rf /opt/revolt/web && cp -a /opt/revolt/web-dist /opt/revolt/web
find /opt/revolt/web -type f \( -name '*.js' -o -name '*.html' \) -print0 | xargs -0 -r sed -i \
  -e "s|__VITE_HOST__|${HOST_ONLY}|g" \
  -e "s|__VITE_API_URL__|${PUBLIC_URL}/api|g" \
  -e 's|"__VITE_WS_URL__"|void 0|g' \
  -e 's|"__VITE_MEDIA_URL__"|void 0|g' \
  -e 's|"__VITE_PROXY_URL__"|void 0|g' \
  -e 's|"__VITE_GIFBOX_URL__"|void 0|g' \
  -e 's|"__VITE_RNNOISE_WORKLET_CDN_URL__"|void 0|g'

# ---- Wait for RabbitMQ --------------------------------------------------------
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/${RABBITMQ_HOST}/${RABBITMQ_PORT:-5672}") 2>/dev/null; then break; fi
  [ "$i" = 60 ] && die "RabbitMQ at ${RABBITMQ_HOST} did not answer"
  log "waiting for RabbitMQ (${i})"; sleep 2
done

# ---- Run ------------------------------------------------------------------------
cd /opt/revolt/run
export RUST_LOG="${RUST_LOG:-info}"
export HOST="127.0.0.1:14703"   # events (bonfire) listen address
pids=()
start() { log "starting $1"; "/opt/revolt/bin/$1" & pids+=($!); }

start revolt-delta
# Let the API run its database migrations before the other services start.
for i in $(seq 1 90); do
  if (exec 3<>/dev/tcp/127.0.0.1/14702) 2>/dev/null; then break; fi
  sleep 2
done
start revolt-bonfire
start revolt-autumn
start revolt-january
start revolt-crond
start revolt-pushd
log "starting caddy on :${PORT} for ${PUBLIC_URL}"
caddy run --config /opt/revolt/Caddyfile --adapter caddyfile & pids+=($!)

trap 'kill -TERM "${pids[@]}" 2>/dev/null; wait; exit 0' TERM INT
set +e
wait -n "${pids[@]}"
code=$?
log "a process exited (code ${code}); stopping the container so Railway restarts it"
kill -TERM "${pids[@]}" 2>/dev/null
exit 1
