#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request

ROOT_DIR = Path(__file__).resolve().parent.parent
ENVS_DIR = ROOT_DIR / "envs"
LOGS_DIR = ROOT_DIR / "logs"
PLATFORM_DIR = ROOT_DIR / "platform"

CREATE_SCRIPT = PLATFORM_DIR / "create_env.sh"
DESTROY_SCRIPT = PLATFORM_DIR / "destroy_env.sh"
SIMULATE_SCRIPT = PLATFORM_DIR / "simulate_outage.sh"

app = Flask(__name__)


def now_epoch() -> int:
    return int(datetime.now(timezone.utc).timestamp())


def parse_created_at(created_at: str) -> int:
    dt = datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ")
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def load_state(env_id: str) -> dict | None:
    state_file = ENVS_DIR / f"{env_id}.json"
    if not state_file.exists():
        return None

    with state_file.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_last_lines(file_path: Path, limit: int) -> list[str]:
    if not file_path.exists():
        return []

    with file_path.open("r", encoding="utf-8") as f:
        lines = f.readlines()

    return [line.rstrip("\n") for line in lines[-limit:]]


@app.post("/envs")
def create_env():
    payload = request.get_json(silent=True) or {}
    name = payload.get("name")
    ttl = payload.get("ttl", 1800)

    if not name:
        return jsonify({"error": "Field 'name' is required"}), 400

    try:
        ttl = int(ttl)
    except (TypeError, ValueError):
        return jsonify({"error": "Field 'ttl' must be an integer"}), 400

    result = subprocess.run(
        ["bash", str(CREATE_SCRIPT), name, str(ttl)],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return jsonify(
            {
                "error": "Failed to create environment",
                "details": result.stderr.strip() or result.stdout.strip(),
            }
        ), 500

    return jsonify(
        {
            "message": "Environment created",
            "output": result.stdout.strip(),
        }
    ), 201


@app.get("/envs")
def list_envs():
    envs = []

    for state_file in sorted(ENVS_DIR.glob("*.json")):
        try:
            with state_file.open("r", encoding="utf-8") as f:
                data = json.load(f)

            created_epoch = parse_created_at(data["created_at"])
            ttl = int(data["ttl"])
            expires_at = created_epoch + ttl
            ttl_remaining = max(0, expires_at - now_epoch())

            envs.append(
                {
                    "id": data["id"],
                    "name": data["name"],
                    "status": data.get("status", "unknown"),
                    "created_at": data["created_at"],
                    "ttl": ttl,
                    "ttl_remaining": ttl_remaining,
                    "route_path": data.get("route_path", f"/{data['id']}/"),
                }
            )
        except Exception as exc:
            envs.append(
                {
                    "file": state_file.name,
                    "error": f"Failed to read state file: {exc}",
                }
            )

    return jsonify(envs), 200


@app.delete("/envs/<env_id>")
def destroy_env(env_id: str):
    result = subprocess.run(
        ["bash", str(DESTROY_SCRIPT), env_id],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return jsonify(
            {
                "error": f"Failed to destroy environment {env_id}",
                "details": result.stderr.strip() or result.stdout.strip(),
            }
        ), 500

    return jsonify(
        {
            "message": f"Environment {env_id} destroyed",
            "output": result.stdout.strip(),
        }
    ), 200


@app.get("/envs/<env_id>/logs")
def get_env_logs(env_id: str):
    log_file = LOGS_DIR / env_id / "app.log"
    lines = read_last_lines(log_file, 100)

    return jsonify(
        {
            "env_id": env_id,
            "lines": lines,
        }
    ), 200


@app.get("/envs/<env_id>/health")
def get_env_health(env_id: str):
    health_file = LOGS_DIR / env_id / "health.log"
    lines = read_last_lines(health_file, 10)

    return jsonify(
        {
            "env_id": env_id,
            "checks": lines,
        }
    ), 200


@app.post("/envs/<env_id>/outage")
def simulate_outage(env_id: str):
    payload = request.get_json(silent=True) or {}
    mode = payload.get("mode")

    if not mode:
        return jsonify({"error": "Field 'mode' is required"}), 400

    result = subprocess.run(
        ["bash", str(SIMULATE_SCRIPT), "--env", env_id, "--mode", mode],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return jsonify(
            {
                "error": f"Failed to simulate outage for {env_id}",
                "details": result.stderr.strip() or result.stdout.strip(),
            }
        ), 500

    return jsonify(
        {
            "message": f"Outage simulation '{mode}' executed for {env_id}",
            "output": result.stdout.strip(),
        }
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
