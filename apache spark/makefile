# =============================================================================
#  Makefile — Apache Spark on Docker
#  Image  : apache/spark:3.5.0
#  Usage  : make <target>   |   make help
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: help \
        up down restart status pull \
        logs logs-master logs-worker-1 logs-worker-2 logs-worker-3 \
        logs-history logs-jupyter \
        submit submit-custom submit-scala \
        shell shell-worker-1 shell-worker-2 shell-worker-3 \
        pyspark spark-shell spark-sql \
        workers-status worker-up worker-down \
        history-clear \
        health wait-ready \
        clean clean-logs clean-data clean-all \
        ps port-check

# ── Variables ─────────────────────────────────────────────────────────────────
COMPOSE          := docker compose
MASTER           := spark-master
SPARK_HOME       := /opt/spark
MASTER_URL       := spark://$(MASTER):7077
EXECUTOR_MEMORY  ?= 1G
EXECUTOR_CORES   ?= 4
SCRIPT           ?= apps/sample_job.py

# Colours for terminal output
BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
AMBER := \033[33m
RED   := \033[31m
RESET := \033[0m

# =============================================================================
#  HELP
# =============================================================================
help:
	@echo ""
	@echo "$(BOLD)  Apache Spark on Docker — available targets$(RESET)"
	@echo ""
	@echo "$(CYAN)  CLUSTER$(RESET)"
	@echo "    up                Start the full cluster (master + workers + history + jupyter)"
	@echo "    down              Stop and remove all containers"
	@echo "    restart           Restart all services"
	@echo "    status            Show container names, state, and ports"
	@echo "    pull              Pull the latest apache/spark image"
	@echo "    health            Print health of every container"
	@echo "    wait-ready        Block until master is reachable (CI use)"
	@echo ""
	@echo "$(CYAN)  LOGS$(RESET)"
	@echo "    logs              Tail all service logs"
	@echo "    logs-master       Tail spark-master only"
	@echo "    logs-worker-1     Tail spark-worker-1 only"
	@echo "    logs-worker-2     Tail spark-worker-2 only"
	@echo "    logs-worker-3     Tail spark-worker-3 only"
	@echo "    logs-history      Tail history server only"
	@echo "    logs-jupyter      Tail Jupyter only"
	@echo ""
	@echo "$(CYAN)  JOB SUBMISSION$(RESET)"
	@echo "    submit            Submit apps/sample_job.py to the cluster"
	@echo "    submit-custom     Submit a custom Python script  SCRIPT=apps/my_job.py"
	@echo "    submit-scala      Submit a JAR                   JAR=apps/job.jar CLASS=com.example.Main"
	@echo ""
	@echo "$(CYAN)  SHELLS$(RESET)"
	@echo "    shell             bash on spark-master"
	@echo "    shell-worker-1    bash on spark-worker-1"
	@echo "    shell-worker-2    bash on spark-worker-2"
	@echo "    shell-worker-3    bash on spark-worker-3"
	@echo "    pyspark           PySpark interactive REPL"
	@echo "    spark-shell       Scala spark-shell REPL"
	@echo "    spark-sql         Spark SQL interactive shell"
	@echo ""
	@echo "$(CYAN)  WORKERS$(RESET)"
	@echo "    workers-status    Show registered workers from Master UI"
	@echo "    worker-up         Start a stopped worker   NAME=spark-worker-1"
	@echo "    worker-down       Stop a running worker    NAME=spark-worker-1"
	@echo ""
	@echo "$(CYAN)  CLEANUP$(RESET)"
	@echo "    clean             Remove containers + orphans (keep data & logs)"
	@echo "    clean-logs        Delete event logs in ./logs"
	@echo "    clean-data        Delete output files in ./data/output"
	@echo "    clean-all         Full wipe — containers, logs, output"
	@echo ""
	@echo "$(CYAN)  UTILS$(RESET)"
	@echo "    history-clear     Clear History Server event logs and restart it"
	@echo "    port-check        Show which host ports are in use"
	@echo "    ps                Alias for status"
	@echo ""
	@echo "$(AMBER)  Overridable variables$(RESET)"
	@echo "    EXECUTOR_MEMORY   (default: 1G)    e.g. make submit EXECUTOR_MEMORY=2G"
	@echo "    EXECUTOR_CORES    (default: 4)     e.g. make submit EXECUTOR_CORES=6"
	@echo "    SCRIPT            (default: apps/sample_job.py)"
	@echo ""

# =============================================================================
#  CLUSTER LIFECYCLE
# =============================================================================
up:
	@echo "$(BOLD)$(GREEN)▶ Starting Spark cluster...$(RESET)"
	@mkdir -p data logs apps notebooks
	@$(COMPOSE) up -d
	@echo ""
	@echo "$(GREEN)  ✓ Cluster started$(RESET)"
	@echo ""
	@echo "  $(BOLD)Spark Master UI$(RESET)   →  http://localhost:8080"
	@echo "  $(BOLD)Worker 1 UI$(RESET)       →  http://localhost:8081"
	@echo "  $(BOLD)Worker 2 UI$(RESET)       →  http://localhost:8082"
	@echo "  $(BOLD)Worker 3 UI$(RESET)       →  http://localhost:8083"
	@echo "  $(BOLD)History Server$(RESET)    →  http://localhost:18080"
	@echo "  $(BOLD)Jupyter Lab$(RESET)       →  http://localhost:8888"
	@echo ""
	@echo "  Run $(CYAN)make wait-ready$(RESET) to block until the master is reachable."
	@echo "  Run $(CYAN)make submit$(RESET) to run the sample job."
	@echo ""

down:
	@echo "$(BOLD)$(RED)▶ Stopping Spark cluster...$(RESET)"
	@$(COMPOSE) down
	@echo "$(GREEN)  ✓ All containers stopped$(RESET)"

restart:
	@echo "$(BOLD)$(AMBER)▶ Restarting all services...$(RESET)"
	@$(COMPOSE) restart
	@echo "$(GREEN)  ✓ Done$(RESET)"

status ps:
	@$(COMPOSE) ps

pull:
	@echo "$(BOLD)▶ Pulling latest apache/spark image...$(RESET)"
	@docker pull apache/spark:3.5.0
	@echo "$(GREEN)  ✓ Image up to date$(RESET)"

health:
	@echo "$(BOLD)▶ Container health$(RESET)"
	@docker inspect --format \
		'  {{printf "%-22s" .Name}}  {{.State.Status}}  health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' \
		$$($(COMPOSE) ps -q) 2>/dev/null || echo "  No containers running."

wait-ready:
	@echo "$(BOLD)▶ Waiting for Spark Master on :8080 ...$(RESET)"
	@until curl -sf http://localhost:8080 > /dev/null; do \
		printf "."; sleep 2; \
	done
	@echo ""
	@echo "$(GREEN)  ✓ Master is reachable$(RESET)"

# =============================================================================
#  LOGS
# =============================================================================
logs:
	@$(COMPOSE) logs -f

logs-master:
	@$(COMPOSE) logs -f spark-master

logs-worker-1:
	@$(COMPOSE) logs -f spark-worker-1

logs-worker-2:
	@$(COMPOSE) logs -f spark-worker-2

logs-worker-3:
	@$(COMPOSE) logs -f spark-worker-3

logs-history:
	@$(COMPOSE) logs -f spark-history-server

logs-jupyter:
	@$(COMPOSE) logs -f jupyter

# =============================================================================
#  JOB SUBMISSION
# =============================================================================
submit:
	@echo "$(BOLD)▶ Submitting sample job...$(RESET)"
	@echo "  Master        : $(MASTER_URL)"
	@echo "  Script        : $(SCRIPT)"
	@echo "  Executor mem  : $(EXECUTOR_MEMORY)"
	@echo "  Executor cores: $(EXECUTOR_CORES)"
	@echo "  App UI        : http://localhost:4040  (active while job runs)"
	@echo ""
	@docker exec $(MASTER) \
		$(SPARK_HOME)/bin/spark-submit \
		--master $(MASTER_URL) \
		--executor-memory $(EXECUTOR_MEMORY) \
		--total-executor-cores $(EXECUTOR_CORES) \
		$(SPARK_HOME)/$(SCRIPT)

submit-custom:
	@if [ -z "$(SCRIPT)" ]; then \
		echo "$(RED)  ✗ Provide a script: make submit-custom SCRIPT=apps/my_job.py$(RESET)"; exit 1; \
	fi
	@echo "$(BOLD)▶ Submitting $(SCRIPT)...$(RESET)"
	@docker exec $(MASTER) \
		$(SPARK_HOME)/bin/spark-submit \
		--master $(MASTER_URL) \
		--executor-memory $(EXECUTOR_MEMORY) \
		--total-executor-cores $(EXECUTOR_CORES) \
		$(SPARK_HOME)/$(SCRIPT)

submit-scala:
	@if [ -z "$(JAR)" ] || [ -z "$(CLASS)" ]; then \
		echo "$(RED)  ✗ Provide JAR and CLASS: make submit-scala JAR=apps/job.jar CLASS=com.example.Main$(RESET)"; exit 1; \
	fi
	@echo "$(BOLD)▶ Submitting $(JAR) ($(CLASS))...$(RESET)"
	@docker exec $(MASTER) \
		$(SPARK_HOME)/bin/spark-submit \
		--master $(MASTER_URL) \
		--class $(CLASS) \
		--executor-memory $(EXECUTOR_MEMORY) \
		--total-executor-cores $(EXECUTOR_CORES) \
		$(SPARK_HOME)/$(JAR)

# =============================================================================
#  INTERACTIVE SHELLS
# =============================================================================
shell:
	@echo "$(BOLD)▶ Opening bash on $(MASTER)...$(RESET)"
	@docker exec -it $(MASTER) bash

shell-worker-1:
	@docker exec -it spark-worker-1 bash

shell-worker-2:
	@docker exec -it spark-worker-2 bash

shell-worker-3:
	@docker exec -it spark-worker-3 bash

pyspark:
	@echo "$(BOLD)▶ Starting PySpark REPL  (App UI → http://localhost:4040)$(RESET)"
	@docker exec -it $(MASTER) \
		$(SPARK_HOME)/bin/pyspark \
		--master $(MASTER_URL)

spark-shell:
	@echo "$(BOLD)▶ Starting Scala spark-shell  (App UI → http://localhost:4040)$(RESET)"
	@docker exec -it $(MASTER) \
		$(SPARK_HOME)/bin/spark-shell \
		--master $(MASTER_URL)

spark-sql:
	@echo "$(BOLD)▶ Starting Spark SQL shell  (App UI → http://localhost:4040)$(RESET)"
	@docker exec -it $(MASTER) \
		$(SPARK_HOME)/bin/spark-sql \
		--master $(MASTER_URL)

# =============================================================================
#  WORKER MANAGEMENT
# =============================================================================
workers-status:
	@echo "$(BOLD)▶ Workers registered with master$(RESET)"
	@curl -sf http://localhost:8080/json/ \
		| python3 -c "\
import sys, json; \
d = json.load(sys.stdin); \
workers = d.get('workers', []); \
print(f'  Total: {len(workers)}'); \
[print(f'  {w[\"id\"][:30]:<32} {w[\"state\"]:<10} cores={w[\"cores\"]} mem={w[\"memory\"]}MB') for w in workers]" \
		2>/dev/null || echo "  $(AMBER)Master UI not reachable — is the cluster running?$(RESET)"

worker-up:
	@if [ -z "$(NAME)" ]; then \
		echo "$(RED)  ✗ Specify worker: make worker-up NAME=spark-worker-1$(RESET)"; exit 1; \
	fi
	@echo "$(BOLD)▶ Starting $(NAME)...$(RESET)"
	@$(COMPOSE) start $(NAME)

worker-down:
	@if [ -z "$(NAME)" ]; then \
		echo "$(RED)  ✗ Specify worker: make worker-down NAME=spark-worker-1$(RESET)"; exit 1; \
	fi
	@echo "$(BOLD)▶ Stopping $(NAME)...$(RESET)"
	@$(COMPOSE) stop $(NAME)

# =============================================================================
#  CLEANUP
# =============================================================================
clean:
	@echo "$(BOLD)$(RED)▶ Removing containers...$(RESET)"
	@$(COMPOSE) down --remove-orphans
	@echo "$(GREEN)  ✓ Done  (./data and ./logs preserved)$(RESET)"

clean-logs:
	@echo "$(BOLD)▶ Clearing event logs in ./logs ...$(RESET)"
	@rm -f logs/*.inprogress logs/*.json logs/local-* logs/app-*
	@echo "$(GREEN)  ✓ Logs cleared$(RESET)"

clean-data:
	@echo "$(BOLD)▶ Clearing ./data/output ...$(RESET)"
	@rm -rf data/output
	@echo "$(GREEN)  ✓ Output data cleared$(RESET)"

clean-all: clean clean-logs clean-data
	@echo "$(GREEN)  ✓ Full wipe complete$(RESET)"

# =============================================================================
#  UTILS
# =============================================================================
history-clear: clean-logs
	@echo "$(BOLD)▶ Restarting History Server to pick up cleared logs...$(RESET)"
	@$(COMPOSE) restart spark-history-server
	@echo "$(GREEN)  ✓ History Server restarted$(RESET)"

port-check:
	@echo "$(BOLD)▶ Checking host ports used by this cluster$(RESET)"
	@for port in 7077 8080 8081 8082 8083 18080 8888 4040; do \
		status=$$(lsof -ti :$$port 2>/dev/null | head -1); \
		if [ -n "$$status" ]; then \
			echo "  $(GREEN)●$(RESET) :$$port  in use (pid $$status)"; \
		else \
			echo "  $(AMBER)○$(RESET) :$$port  free"; \
		fi; \
	done
