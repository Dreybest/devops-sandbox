#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
TTL="${2:-1800}"

if [[ -z "$NAME" ]]; then
  echo "Usage: bash platform/create_env.sh <name> [ttl_seconds]"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVS_DIR="$ROOT_DIR/envs"
LOGS_DIR="$ROOT_DIR/logs"
NGINX_CONF_DIR="$ROOT_DIR/nginx/conf.d"

mkdir -p "$ENVS_DIR" "$LOGS_DIR" "$NGINX_CONF_DIR"

ENV_ID="env-$(date +%s)-$RANDOM"
CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STATUS="active"

STATE_FILE="$ENVS_DIR/${ENV_ID}.json"
STATE_TMP_FILE="$ENVS_DIR/${ENV_ID}.json.tmp"
ENV_LOG_DIR="$LOGS_DIR/$ENV_ID"
mkdir -p "$ENV_LOG_DIR"

NETWORK_NAME="${ENV_ID}-net"
PLATFORM_NETWORK="sandbox-platform"
CONTAINER_NAME="${ENV_ID}-app"
ROUTE_PATH="/${ENV_ID}/"
NGINX_CONF_FILE="$NGINX_CONF_DIR/${ENV_ID}.conf"
PID_FILE="$ENV_LOG_DIR/log-shipper.pid"
IMAGE_NAME="devops-sandbox-demo:latest"

docker network create "$NETWORK_NAME" >/dev/null

if ! docker network inspect "$PLATFORM_NETWORK" >/dev/null 2>&1; then
  echo "Shared platform network '$PLATFORM_NETWORK' does not exist."
  echo "Start nginx first with docker compose up -d nginx"
  exit 1
fi

docker build -t "$IMAGE_NAME" -f "$ROOT_DIR/platform/Dockerfile.demo" "$ROOT_DIR" >/dev/null

CONTAINER_ID="$(docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK_NAME" \
  --label "sandbox.env=$ENV_ID" \
  --label "sandbox.role=app" \
  -e SANDBOX_ENV_ID="$ENV_ID" \
  -e SANDBOX_ENV_NAME="$NAME" \
  "$IMAGE_NAME")"

docker network connect "$PLATFORM_NETWORK" "$CONTAINER_NAME" >/dev/null

cat >"$STATE_TMP_FILE" <<EOF
{
  "id": "$ENV_ID",
  "name": "$NAME",
  "created_at": "$CREATED_AT",
  "ttl": $TTL,
  "status": "$STATUS",
  "container_name": "$CONTAINER_NAME",
  "container_id": "$CONTAINER_ID",
  "network_name": "$NETWORK_NAME",
  "route_path": "$ROUTE_PATH"
}
EOF

mv "$STATE_TMP_FILE" "$STATE_FILE"

cat >"$NGINX_CONF_FILE" <<EOF
location ${ROUTE_PATH} {
    proxy_pass http://${CONTAINER_NAME}:80/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF

docker exec devops-sandbox-nginx nginx -s reload >/dev/null

nohup docker logs -f "$CONTAINER_NAME" >> "$ENV_LOG_DIR/app.log" 2>&1 &
echo $! > "$PID_FILE"

echo "Environment created successfully"
echo "Env ID: $ENV_ID"
echo "Name: $NAME"
echo "TTL: $TTL seconds"
echo "URL: http://localhost:8080${ROUTE_PATH}"
