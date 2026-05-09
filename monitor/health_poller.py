#!/usr/bin/env python3
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import URLError, HTTPError
from urllib.request import urlopen

ROOT_DIR = Path(__file__).resolve().parent.parent
ENVS_DIR = ROOT_DIR / "envs"
LOGS_DIR = ROOT_DIR / "logs"
CHECK_INTERVAL = 30
FAILURE_THRESHOLD = 3


def now_utc_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_env_state(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_env_state(path: Path, data: dict) -> None:
    tmp_path = path.with_suffix(".json.tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp_path, path)


def check_health(env_id: str) -> tuple[int, float]:
    url = f"http://localhost:8080/{env_id}/health"
    start = time.perf_counter()

    try:
        with urlopen(url, timeout=10) as response:
            latency_ms = (time.perf_counter() - start) * 1000
            return response.getcode(), latency_ms
    except HTTPError as exc:
        latency_ms = (time.perf_counter() - start) * 1000
        return exc.code, latency_ms
    except URLError:
        latency_ms = (time.perf_counter() - start) * 1000
        return 0, latency_ms
    except Exception:
        latency_ms = (time.perf_counter() - start) * 1000
        return 0, latency_ms


def append_health_log(env_id: str, status_code: int, latency_ms: float) -> None:
    env_log_dir = LOGS_DIR / env_id
    env_log_dir.mkdir(parents=True, exist_ok=True)
    log_file = env_log_dir / "health.log"

    with log_file.open("a", encoding="utf-8") as f:
        f.write(f"{now_utc_iso()} status={status_code} latency_ms={latency_ms:.2f}\n")


def main() -> None:
    failure_counts: dict[str, int] = {}

    while True:
        for state_file in ENVS_DIR.glob("*.json"):
            try:
                state = load_env_state(state_file)
                env_id = state["id"]

                status_code, latency_ms = check_health(env_id)
                append_health_log(env_id, status_code, latency_ms)

                if 200 <= status_code < 300:
                    failure_counts[env_id] = 0
                    if state.get("status") == "degraded":
                        state["status"] = "active"
                        save_env_state(state_file, state)
                else:
                    failure_counts[env_id] = failure_counts.get(env_id, 0) + 1

                    if failure_counts[env_id] >= FAILURE_THRESHOLD:
                        if state.get("status") != "degraded":
                            state["status"] = "degraded"
                            save_env_state(state_file, state)
                            print(f"[WARN] {now_utc_iso()} {env_id} marked degraded after 3 consecutive failures")

            except Exception as exc:
                print(f"[ERROR] Failed to process {state_file.name}: {exc}")

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
