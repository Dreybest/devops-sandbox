SHELL := /bin/bash

ENV ?=
MODE ?=

.PHONY: up down create destroy logs health simulate clean

up:
	@mkdir -p logs/nginx logs/archived envs nginx/conf.d
	@docker compose up -d nginx api
	@nohup python3 monitor/health_poller.py > logs/health_poller.out 2>&1 &
	@nohup bash platform/cleanup_daemon.sh > logs/cleanup_daemon.out 2>&1 &
	@echo "Platform started."
	@echo "Nginx: http://localhost:8080"
	@echo "API:   http://localhost:5000"

down:
	@for file in envs/*.json; do \
		[ -e "$$file" ] || continue; \
		env_id=$$(basename "$$file" .json); \
		bash platform/destroy_env.sh "$$env_id"; \
	done
	@docker compose down
	@pkill -f "monitor/health_poller.py" >/dev/null 2>&1 || true
	@pkill -f "platform/cleanup_daemon.sh" >/dev/null 2>&1 || true
	@echo "Platform stopped."

create:
	@read -p "Enter environment name: " NAME_INPUT; \
	read -p "Enter TTL in seconds [default: 1800]: " TTL_INPUT; \
	TTL_INPUT=$${TTL_INPUT:-1800}; \
	bash platform/create_env.sh "$$NAME_INPUT" "$$TTL_INPUT"

destroy:
	@if [ -z "$(ENV)" ]; then \
		echo "Usage: make destroy ENV=env-abc123"; \
		exit 1; \
	fi
	@bash platform/destroy_env.sh "$(ENV)"

logs:
	@if [ -z "$(ENV)" ]; then \
		echo "Usage: make logs ENV=env-abc123"; \
		exit 1; \
	fi
	@touch logs/$(ENV)/app.log
	@tail -n 100 -f logs/$(ENV)/app.log

health:
	@echo "Environment health summary:"
	@for file in envs/*.json; do \
		[ -e "$$file" ] || continue; \
		python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(f"{d[\"id\"]} status={d.get(\"status\",\"unknown\")} ttl={d.get(\"ttl\")}")' "$$file"; \
	done

simulate:
	@if [ -z "$(ENV)" ] || [ -z "$(MODE)" ]; then \
		echo "Usage: make simulate ENV=env-abc123 MODE=crash"; \
		exit 1; \
	fi
	@bash platform/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

clean:
	@rm -rf logs/* envs/* nginx/conf.d/*
	@mkdir -p logs/archived logs/nginx envs nginx/conf.d
	@echo "State, logs, and generated nginx configs wiped."
