#!/usr/bin/env bash
set -euo pipefail

ENV_ID="${1:-}"

if [[ -z "$ENV_ID" ]]; then
  echo "Usage: bash platform/destroy_env.sh <env_id>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVS_DIR="$ROOT_DIR/envs"
LOGS_DIR="$ROOT_DIR/logs"
NGINX_CONF_DIR="$ROOT_DIR/nginx/conf.d"
ARCHIVE_DIR="$LOGS_DIR/archived/$ENV_ID"

STATE_FILE="$ENVS_DIR/${ENV_ID}.json"
NGINX_CONF_FILE="$NGINX_CONF_DIR/${ENV_ID}.conf"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found for env: $ENV_ID"
  exit 1
fi

CONTAINER_IDS="$(docker ps -aq --filter "label=sandbox.env=${ENV_ID}")"
NETWORK_NAME="${ENV_ID}-net"
ENV_LOG_DIR="$LOGS_DIR/$ENV_ID"
PID_FILE="$ENV_LOG_DIR/log-shipper.pid"

mkdir -p "$ARCHIVE_DIR"

if [[ -n "$CONTAINER_IDS" ]]; then
  echo "$CONTAINER_IDS" | xargs -r docker stop >/dev/null
  echo "$CONTAINER_IDS" | xargs -r docker rm >/dev/null
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network rm "$NETWORK_NAME" >/dev/null
fi

if [[ -f "$PID_FILE" ]]; then
  LOG_PID="$(cat "$PID_FILE")"
  if kill -0 "$LOG_PID" >/dev/null 2>&1; then
    kill "$LOG_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_FILE"
fi

if [[ -f "$NGINX_CONF_FILE" ]]; then
  rm -f "$NGINX_CONF_FILE"
fi

if [[ -d "$ENV_LOG_DIR" ]]; then
  cp -R "$ENV_LOG_DIR"/. "$ARCHIVE_DIR"/ 2>/dev/null || true
  rm -rf "$ENV_LOG_DIR"
fi

rm -f "$STATE_FILE"

echo "Environment destroyed successfully"
echo "Env ID: $ENV_ID"
echo "Archived logs: $ARCHIVE_DIR"
echo
echo "Next steps:"
echo "1. Add Nginx reload after config deletion"
echo "2. Make sure create_env.sh stores log shipper PID"
echo "3. Add stronger state parsing if container/network names change later"
