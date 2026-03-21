# ──────────────────────────────────────────────────────────────────────────────
# Kafka Stack — Makefile
# Usage: make <target>
# ──────────────────────────────────────────────────────────────────────────────

COMPOSE    = docker compose
KAFKA_EXEC = $(COMPOSE) exec kafka
BROKER     = kafka:9092

.PHONY: help up down restart logs ps \
        create-topic list-topics describe-topic delete-topic \
        produce consume \
        list-schemas \
        list-connectors \
        health

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Stack lifecycle ────────────────────────────────────────────────────────────
up: ## Start the full stack (detached)
	$(COMPOSE) up -d
	@echo ""
	@echo "  Kafka UI      → http://localhost:8080"
	@echo "  Control Center→ http://localhost:9021"
	@echo "  Schema Registry→ http://localhost:8081"
	@echo "  REST Proxy    → http://localhost:8082"
	@echo "  Kafka Connect → http://localhost:8083"

down: ## Stop and remove containers (keeps volumes)
	$(COMPOSE) down

destroy: ## Stop and remove containers AND volumes
	$(COMPOSE) down -v

restart: ## Restart all services
	$(COMPOSE) restart

logs: ## Tail logs for all services
	$(COMPOSE) logs -f

logs-%: ## Tail logs for a specific service  e.g. make logs-kafka
	$(COMPOSE) logs -f $*

ps: ## Show running containers
	$(COMPOSE) ps

# ── Health checks ─────────────────────────────────────────────────────────────
health: ## Check health of all services
	@echo "=== Zookeeper ===" && \
	  docker exec zookeeper bash -c "echo ruok | nc localhost 2181" && \
	  echo ""
	@echo "=== Kafka ===" && \
	  docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 | head -5 && \
	  echo ""
	@echo "=== Schema Registry ===" && \
	  curl -s http://localhost:8081/subjects && echo ""
	@echo "=== Kafka Connect ===" && \
	  curl -s http://localhost:8083/ | python3 -m json.tool

# ── Topic operations ──────────────────────────────────────────────────────────
create-topic: ## Create a topic. Usage: make create-topic TOPIC=my-topic [PARTITIONS=3] [REPLICAS=1]
	$(KAFKA_EXEC) kafka-topics \
		--bootstrap-server $(BROKER) \
		--create \
		--if-not-exists \
		--topic $(TOPIC) \
		--partitions $(or $(PARTITIONS),3) \
		--replication-factor $(or $(REPLICAS),1)

list-topics: ## List all topics
	$(KAFKA_EXEC) kafka-topics --bootstrap-server $(BROKER) --list

describe-topic: ## Describe a topic. Usage: make describe-topic TOPIC=my-topic
	$(KAFKA_EXEC) kafka-topics --bootstrap-server $(BROKER) --describe --topic $(TOPIC)

delete-topic: ## Delete a topic. Usage: make delete-topic TOPIC=my-topic
	$(KAFKA_EXEC) kafka-topics --bootstrap-server $(BROKER) --delete --topic $(TOPIC)

# ── Produce / Consume ─────────────────────────────────────────────────────────
produce: ## Produce messages interactively. Usage: make produce TOPIC=my-topic
	$(KAFKA_EXEC) kafka-console-producer \
		--bootstrap-server $(BROKER) \
		--topic $(TOPIC)

consume: ## Consume messages from beginning. Usage: make consume TOPIC=my-topic
	$(KAFKA_EXEC) kafka-console-consumer \
		--bootstrap-server $(BROKER) \
		--topic $(TOPIC) \
		--from-beginning \
		--property print.key=true \
		--property print.timestamp=true

consume-group: ## Consume as a group. Usage: make consume-group TOPIC=my-topic GROUP=my-group
	$(KAFKA_EXEC) kafka-console-consumer \
		--bootstrap-server $(BROKER) \
		--topic $(TOPIC) \
		--group $(or $(GROUP),test-group) \
		--from-beginning

list-groups: ## List consumer groups
	$(KAFKA_EXEC) kafka-consumer-groups --bootstrap-server $(BROKER) --list

describe-group: ## Describe consumer group. Usage: make describe-group GROUP=my-group
	$(KAFKA_EXEC) kafka-consumer-groups \
		--bootstrap-server $(BROKER) \
		--describe \
		--group $(GROUP)

# ── Schema Registry ───────────────────────────────────────────────────────────
list-schemas: ## List all registered schemas
	@curl -s http://localhost:8081/subjects | python3 -m json.tool

# ── Kafka Connect ─────────────────────────────────────────────────────────────
list-connectors: ## List all connectors
	@curl -s http://localhost:8083/connectors | python3 -m json.tool

connector-status: ## Get connector status. Usage: make connector-status CONNECTOR=my-connector
	@curl -s http://localhost:8083/connectors/$(CONNECTOR)/status | python3 -m json.tool