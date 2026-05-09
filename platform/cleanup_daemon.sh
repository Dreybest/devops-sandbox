#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVS_DIR="$ROOT_DIR/envs"
LOGS_DIR="$ROOT_DIR/logs"
CLEANUP_LOG="$LOGS_DIR/cleanup.log"
DESTROY_SCRIPT="$ROOT_DIR/platform/destroy_env.sh"

mkdir -p "$ENVS_DIR" "$LOGS_DIR"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(timestamp)] $*" | tee -a "$CLEANUP_LOG"
}

expiry_epoch() {
  local created_at="$1"
  local ttl="$2"
  local created_epoch

  created_epoch="$(date -d "$created_at" +%s 2>/dev/null || true)"
  if [[ -z "$created_epoch" ]]; then
    echo ""
    return
  fi

  echo $((created_epoch + ttl))
}

log "Cleanup daemon started. Scanning every 60 seconds."

while true; do
  shopt -s nullglob

  for state_file in "$ENVS_DIR"/*.json; do
    env_id="$(basename "$state_file" .json)"

    created_at="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["created_at"])' "$state_file" 2>/dev/null || true)"
    ttl="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ttl"])' "$state_file" 2>/dev/null || true)"

    if [[ -z "$created_at" || -z "$ttl" ]]; then
      log "Skipping $env_id because created_at or ttl could not be read."
      continue
    fi

    now_epoch="$(date -u +%s)"
    expires_epoch="$(expiry_epoch "$created_at" "$ttl")"

    if [[ -z "$expires_epoch" ]]; then
      log "Skipping $env_id because created_at is invalid: $created_at"
      continue
    fi

    if (( now_epoch > expires_epoch )); then
      log "Environment $env_id expired. Destroying now."
      if bash "$DESTROY_SCRIPT" "$env_id" >>"$CLEANUP_LOG" 2>&1; then
        log "Environment $env_id destroyed successfully by cleanup daemon."
      else
        log "Failed to destroy expired environment $env_id."
      fi
    else
      remaining=$((expires_epoch - now_epoch))
      log "Environment $env_id still active. ${remaining}s remaining."
    fi
  done

  sleep 60
done
