# DevOps Sandbox Platform

A self-service temporary environment platform that lets users create isolated sandbox environments, route traffic to them through Nginx, monitor health, simulate outages, and automatically clean up expired environments.

This project was built for the HNG Stage 5 DevOps task and is designed to run on a single Linux VM.

## Overview

The platform provides:
- short-lived sandbox environments with configurable TTL
- dynamic Nginx routing for each environment
- per-environment state tracking in JSON
- per-environment application and health logs
- outage simulation for chaos testing
- automatic cleanup of expired environments
- a Flask API for platform control
- Makefile shortcuts for common operations

## Architecture

```text
                           +----------------------+
                           |      User/Tester     |
                           +----------+-----------+
                                      |
                                      v
                           +----------------------+
                           |   Nginx Front Door   |
                           |   localhost:8080     |
                           +----------+-----------+
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    v                                   v
          +----------------------+           +----------------------+
          | Sandbox App Env A    |           | Sandbox App Env B    |
          | env-xxxxx            |           | env-yyyyy            |
          +----------------------+           +----------------------+

                           +----------------------+
                           |   Flask Control API  |
                           |   localhost:5000     |
                           +----------------------+

                           +----------------------+
                           | Health Poller        |
                           | Cleanup Daemon       |
                           +----------------------+

                           +----------------------+
                           | envs/ and logs/      |
                           | state and archives   |
                           +----------------------+
```

## Repo Structure

```text
devops-sandbox/
+-- platform/
¦   +-- api.py
¦   +-- cleanup_daemon.sh
¦   +-- create_env.sh
¦   +-- demo_app.py
¦   +-- destroy_env.sh
¦   +-- Dockerfile.demo
¦   +-- simulate_outage.sh
+-- nginx/
¦   +-- conf.d/
¦   +-- nginx.conf
+-- monitor/
¦   +-- health_poller.py
+-- logs/
+-- envs/
+-- docker-compose.yml
+-- Makefile
+-- requirements.txt
+-- README.md
```

## Core Components

### 1. Environment Lifecycle

`platform/create_env.sh`:
- accepts a name and optional TTL
- generates a unique environment ID
- creates a dedicated Docker network
- starts the demo app container with `sandbox.env=<ENV_ID>` label
- writes an atomic state file to `envs/<ENV_ID>.json`
- creates an Nginx route in `nginx/conf.d/<ENV_ID>.conf`
- reloads Nginx
- starts log shipping
- prints the environment URL

`platform/destroy_env.sh`:
- stops and removes all containers for the environment label
- removes the dedicated Docker network
- deletes the Nginx config and reloads Nginx
- archives environment logs to `logs/archived/<ENV_ID>/`
- deletes the state file

### 2. Cleanup Daemon

`platform/cleanup_daemon.sh`:
- scans `envs/*.json` every 60 seconds
- checks `created_at + ttl`
- destroys expired environments automatically
- writes timestamped actions to `logs/cleanup.log`

### 3. Dynamic Routing

Nginx runs as a Docker container and acts as the front door for all environments.

Each new environment gets a generated config file in `nginx/conf.d/`.
The main `nginx/nginx.conf` includes all generated route files.

### 4. Log Shipping

This project uses the simple log shipping approach:
- `docker logs -f <container>` runs in the background for each environment
- output is stored in `logs/<ENV_ID>/app.log`
- the background PID is stored and cleaned up on destroy

### 5. Health Monitoring

`monitor/health_poller.py`:
- polls each active environment every 30 seconds
- hits `GET /<env_id>/health` through Nginx
- records timestamp, status, and latency in `logs/<ENV_ID>/health.log`
- marks the environment `degraded` after 3 consecutive failures
- restores status to `active` after successful checks

### 6. Outage Simulation

`platform/simulate_outage.sh` supports:
- `crash`
- `pause`
- `network`
- `recover`
- optional `stress`

A guard prevents simulations from targeting protected platform containers.

### 7. Control API

`platform/api.py` exposes:
- `POST /envs`
- `GET /envs`
- `DELETE /envs/:id`
- `GET /envs/:id/logs`
- `GET /envs/:id/health`
- `POST /envs/:id/outage`

## Prerequisites

Run this on a Linux VM for final grading.

Required:
- Docker
- Docker Compose plugin
- Bash
- Python 3
- Make
- Git

Helpful:
- curl
- nohup

## Environment Variables

Create a `.env` file in the repo root for local configuration or secrets.
Do not commit it.

Example:

```env
APP_ENV=development
```

## Quick Start

From zero to first running environment in under 5 commands:

```bash
git clone <your-repo-url>
cd devops-sandbox
docker compose up -d
nohup python3 monitor/health_poller.py > logs/health_poller.out 2>&1 &
nohup bash platform/cleanup_daemon.sh > logs/cleanup_daemon.out 2>&1 &
```

Create your first environment:

```bash
bash platform/create_env.sh my-first-env 1800
```

Check it:

```bash
curl http://localhost:8080/<env-id>/
curl http://localhost:8080/<env-id>/health
curl http://localhost:5000/envs
```

## Make Targets

```bash
make up
make down
make create
make destroy ENV=env-abc123
make logs ENV=env-abc123
make health
make simulate ENV=env-abc123 MODE=crash
make clean
```

If `make` is unavailable locally, the scripts can still be run manually. Final grading should be done on Linux.

## Manual Usage

### Start Platform Services

```bash
docker compose up -d
nohup python3 monitor/health_poller.py > logs/health_poller.out 2>&1 &
nohup bash platform/cleanup_daemon.sh > logs/cleanup_daemon.out 2>&1 &
```

### Create Environment

```bash
bash platform/create_env.sh <name> [ttl_seconds]
```

Example:

```bash
bash platform/create_env.sh demo-env 1800
```

### Destroy Environment

```bash
bash platform/destroy_env.sh <env_id>
```

### Simulate Outage

```bash
bash platform/simulate_outage.sh --env <env_id> --mode crash
bash platform/simulate_outage.sh --env <env_id> --mode pause
bash platform/simulate_outage.sh --env <env_id> --mode network
bash platform/simulate_outage.sh --env <env_id> --mode recover
```

## API Endpoints

### Create Environment

```http
POST /envs
```

Body:

```json
{
  "name": "my-env",
  "ttl": 1800
}
```

### List Environments

```http
GET /envs
```

Returns active environments and TTL remaining.

### Destroy Environment

```http
DELETE /envs/:id
```

### Get Environment Logs

```http
GET /envs/:id/logs
```

Returns the last 100 lines of `app.log`.

### Get Health Checks

```http
GET /envs/:id/health
```

Returns the last 10 health check results.

### Trigger Outage Simulation

```http
POST /envs/:id/outage
```

Body:

```json
{
  "mode": "crash"
}
```

## Full Demo Walkthrough

### 1. Start the platform

```bash
docker compose up -d
nohup python3 monitor/health_poller.py > logs/health_poller.out 2>&1 &
nohup bash platform/cleanup_daemon.sh > logs/cleanup_daemon.out 2>&1 &
```

### 2. Create a sandbox

```bash
bash platform/create_env.sh demo-video 1800
```

Expected:
- a unique environment ID is generated
- a state file appears in `envs/`
- an Nginx route file is generated
- the environment URL is printed

### 3. Open the environment

```text
http://localhost:8080/<env-id>/
```

Check health:

```bash
curl http://localhost:8080/<env-id>/health
```

### 4. Confirm API visibility

```bash
curl http://localhost:5000/envs
```

Expected:
- the new environment is listed
- TTL remaining is shown

### 5. Simulate outage

```bash
bash platform/simulate_outage.sh --env <env-id> --mode crash
```

Expected:
- the app becomes unreachable
- Nginx returns `502 Bad Gateway`

### 6. Observe degradation

```bash
curl http://localhost:5000/envs/<env-id>/health
curl http://localhost:5000/envs
```

Expected:
- failed checks appear in health logs
- the environment status becomes `degraded`

### 7. Recover the environment

```bash
bash platform/simulate_outage.sh --env <env-id> --mode recover
curl http://localhost:8080/<env-id>/health
curl http://localhost:5000/envs
```

Expected:
- the app becomes healthy again
- after the next successful poll, status returns to `active`

### 8. Destroy manually

```bash
bash platform/destroy_env.sh <env-id>
```

Expected:
- the container is removed
- the network is removed
- the Nginx route is removed
- logs are archived
- the state file is deleted

### 9. Demonstrate auto-destroy

Create another environment with a short TTL:

```bash
bash platform/create_env.sh auto-expire 120
```

Wait for expiration, then show:
- cleanup daemon log entries
- environment disappears from `/envs`
- archived logs appear under `logs/archived/`

## Logging

Application logs:

```text
logs/<env_id>/app.log
```

Health logs:

```text
logs/<env_id>/health.log
```

Cleanup daemon logs:

```text
logs/cleanup.log
```

Archived logs:

```text
logs/archived/<env_id>/
```

## Network Approach

Each environment gets:
- a dedicated Docker network for isolation
- a connection to the shared `sandbox-platform` network so Nginx can proxy traffic to it

This keeps each environment isolated while still allowing central routing through the Nginx container.

## Known Limitations

- Local Windows development can behave differently from the target Linux VM because commands like `nohup`, `pkill`, and `make` are Linux-first.
- The API container currently installs Flask at startup instead of using a production-grade baked image.
- Logging uses a simple `docker logs -f` background process rather than a full aggregator like Loki or Fluentd.
- State management uses JSON files with atomic rename on write, but not full locking.
- Recovery assumes the environment has not already expired and been removed by the cleanup daemon.
- This implementation is optimized for a single-VM demo environment, not multi-node production scale.

## Submission Checklist

- Public GitHub repository
- 3-minute walkthrough video
- Complete README
- Linux VM deployment working at grading time
- Reviewer can bring up the platform and create environments easily
```
