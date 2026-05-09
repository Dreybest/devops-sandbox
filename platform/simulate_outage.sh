#!/usr/bin/env bash
set -euo pipefail

ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_ID="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash platform/simulate_outage.sh --env <env_id> --mode <crash|pause|network|recover|stress>"
      exit 1
      ;;
  esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
  echo "Usage: bash platform/simulate_outage.sh --env <env_id> --mode <crash|pause|network|recover|stress>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$ROOT_DIR/envs/${ENV_ID}.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found for env: $ENV_ID"
  exit 1
fi

CONTAINER_ID="$(docker ps -aq --filter "label=sandbox.env=${ENV_ID}" | head -n 1)"

if [[ -z "$CONTAINER_ID" ]]; then
  echo "No app container found for env: $ENV_ID"
  exit 1
fi

CONTAINER_NAME="$(docker inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's#^/##')"
CONTAINER_ROLE="$(docker inspect --format '{{ index .Config.Labels "sandbox.role" }}' "$CONTAINER_ID" 2>/dev/null || true)"
NETWORK_NAME="${ENV_ID}-net"
PLATFORM_NETWORK="sandbox-platform"

if [[ "$CONTAINER_NAME" == "devops-sandbox-nginx" || "$CONTAINER_ROLE" == "nginx" || "$CONTAINER_ROLE" == "daemon" ]]; then
  echo "Refusing to run outage simulation against protected container: $CONTAINER_NAME"
  exit 1
fi

case "$MODE" in
  crash)
    docker kill "$CONTAINER_ID" >/dev/null
    echo "Crash simulation complete for $ENV_ID"
    ;;
  pause)
    docker pause "$CONTAINER_ID" >/dev/null
    echo "Pause simulation complete for $ENV_ID"
    ;;
  network)
    if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
      docker network disconnect "$NETWORK_NAME" "$CONTAINER_ID" >/dev/null
      echo "Network disconnect simulation complete for $ENV_ID"
    else
      echo "Network not found for env: $NETWORK_NAME"
      exit 1
    fi
    ;;
  recover)
    docker start "$CONTAINER_ID" >/dev/null 2>&1 || true
    docker unpause "$CONTAINER_ID" >/dev/null 2>&1 || true

    if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
      if ! docker network inspect "$NETWORK_NAME" --format '{{json .Containers}}' | grep -q "$CONTAINER_ID"; then
        docker network connect "$NETWORK_NAME" "$CONTAINER_ID" >/dev/null 2>&1 || true
      fi
    fi

    if docker network inspect "$PLATFORM_NETWORK" >/dev/null 2>&1; then
      if ! docker network inspect "$PLATFORM_NETWORK" --format '{{json .Containers}}' | grep -q "$CONTAINER_ID"; then
        docker network connect "$PLATFORM_NETWORK" "$CONTAINER_ID" >/dev/null 2>&1 || true
      fi
    fi

    echo "Recovery complete for $ENV_ID"
    ;;
  stress)
    if docker exec "$CONTAINER_ID" sh -c "command -v stress-ng" >/dev/null 2>&1; then
      docker exec "$CONTAINER_ID" sh -c "timeout 60 stress-ng --cpu 1 --cpu-load 95" >/dev/null 2>&1 || true
      echo "Stress simulation complete for $ENV_ID"
    else
      echo "stress-ng is not installed in container: $CONTAINER_NAME"
      exit 1
    fi
    ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Supported modes: crash, pause, network, recover, stress"
    exit 1
    ;;
esac
