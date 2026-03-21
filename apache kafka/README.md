# Confluent Kafka Stack on Docker

A production-ready local development environment running the full **Confluent Platform 7.6** with a lightweight **Kafka UI** for visual management. Every service is health-checked and starts in the correct dependency order.

---
<img width="1440" height="910" alt="image" src="https://github.com/user-attachments/assets/3f87314b-f00c-4ebf-96df-d31514830be2" />

## Architecture

```
╔══════════════════════════════════════════════════════════════════════╗
║                     docker network: kafka-network                    ║
║                                                                      ║
║   ┌──────────────────┐          ┌────────────────┐                  ║
║   │   Control Center │ monitors │   Zookeeper    │                  ║
║   │     :9021        │◄─ ─ ─ ─ │    :2181       │                  ║
║   └──────────────────┘          └───────┬────────┘                  ║
║                │ monitors               │ coordinates               ║
║                ▼                        ▼                            ║
║   ┌─────────────────────────────────────────────┐  ──► Schema       ║
║   │              Kafka Broker                   │      Registry     ║
║   │       :9092 (internal) · :29092 (host)      │      :8081        ║
║   └──────────┬──────────────────────┬───────────┘                  ║
║              │                      │                               ║
║              ▼                      ▼                               ║
║   ┌──────────────────┐   ┌───────────────────┐                     ║
║   │  Kafka Connect   │   │    REST Proxy     │                     ║
║   │     :8083        │   │      :8082        │                     ║
║   └──────────────────┘   └───────────────────┘                     ║
║                                                                      ║
║   ┌──────────────────────────────────────────────────────────────┐  ║
║   │                Kafka UI (Provectus) :8080                    │  ║
║   └──────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════════╝

External access from host machine:
  Applications → localhost:29092  (Kafka broker)
  Browser      → localhost:8080   (Kafka UI)
  Browser      → localhost:9021   (Control Center)
```

---

## Services at a Glance

| Service            | Image                                           | Internal Port | Host Port | Purpose                         |
|--------------------|-------------------------------------------------|:---:|:---:|--------------------------------|
| Zookeeper          | `confluentinc/cp-zookeeper:7.6.0`               | 2181 | 2181 | Broker coordination            |
| Kafka Broker       | `confluentinc/cp-kafka:7.6.0`                   | 9092 | 29092 | Message streaming engine      |
| Schema Registry    | `confluentinc/cp-schema-registry:7.6.0`         | 8081 | 8081 | Schema management & validation |
| Kafka Connect      | `confluentinc/cp-kafka-connect:7.6.0`           | 8083 | 8083 | Source & sink connectors       |
| REST Proxy         | `confluentinc/cp-kafka-rest:7.6.0`              | 8082 | 8082 | HTTP produce/consume           |
| Control Center     | `confluentinc/cp-enterprise-control-center:7.6.0` | 9021 | 9021 | Enterprise monitoring UI     |
| Kafka UI           | `provectuslabs/kafka-ui:latest`                  | 8080 | 8080 | Lightweight management UI     |

---

## Component Deep Dive

### Zookeeper

**What it is:** A distributed coordination service that Kafka relies on to elect broker leaders, store cluster metadata, and manage consumer group offsets. It is the first service that must be healthy before anything else can start.

**Role in this stack:** Zookeeper starts first and is health-checked with `echo ruok`. The Kafka broker registers itself at `zookeeper:2181` on startup and uses ZK to track which partitions are assigned to which broker. If a broker crashes, Zookeeper detects the failure and triggers automatic leader re-election.

**Real-world scenario — Swiggy food delivery during lunch rush:**

Swiggy runs three Kafka broker nodes to handle order events across 50+ partitions. At 1 PM, one broker node crashes due to a hardware fault. Zookeeper detects the failure within the configured `session.timeout.ms` (~10 seconds), identifies the partitions whose leader was on the lost broker, and promotes a replica leader on a healthy node. The ops team gets a PagerDuty alert but orders continue flowing with zero message loss — all coordination was handled by Zookeeper automatically.

> **Note on KRaft:** Confluent 7.4+ supports KRaft mode (Zookeeper-free, Kafka Raft consensus). This stack uses the classic ZooKeeper mode for maximum compatibility with existing tooling. New production deployments should consider migrating to KRaft.

---

### Kafka Broker

**What it is:** The core Kafka server — the actual message broker. Producers send records to the broker, which stores them durably as ordered, immutable log segments on disk. Consumers pull records at their own pace. The broker manages partitioning, replication, compaction, and retention.

**Two listeners are configured:**

- `PLAINTEXT://kafka:9092` — container-to-container traffic within the Docker network (used by Schema Registry, Connect, Control Center, and Kafka UI)
- `PLAINTEXT_HOST://localhost:29092` — for applications running on your host machine (Spring Boot, Python scripts, Node.js services)

**Real-world scenario — Flipkart Big Billion Days sale:**

During a flash sale, 500,000 "add to cart" events arrive per second into a `cart.events` topic with 48 partitions. The broker stores every event durably for 7 days (configured via `KAFKA_LOG_RETENTION_HOURS: 168`). Twelve consumer services read from this topic concurrently — inventory reservation, personalisation engine, cart abandonment tracker, analytics pipeline — each at their own speed and each maintaining an independent read offset. The broker decouples all of them completely. If the analytics consumer falls two hours behind, it does not slow down order processing by a single millisecond.

**Key broker settings in this stack:**

| Config | Value | Reason |
|--------|-------|--------|
| `NUM_PARTITIONS` | 3 | Default parallelism for new topics |
| `LOG_RETENTION_HOURS` | 168 | Messages kept for 7 days |
| `AUTO_CREATE_TOPICS_ENABLE` | true | Dev convenience — disable in production |
| `GROUP_INITIAL_REBALANCE_DELAY_MS` | 0 | Faster consumer group startup in dev |

---

### Schema Registry

**What it is:** A schema management server that stores versioned Avro, JSON Schema, or Protobuf schemas. Every time a producer writes a message, it registers the schema (or verifies it exists) and embeds a 5-byte schema ID in the message. Consumers use this ID to fetch the correct schema and deserialize the payload.

**Why it matters:** Without Schema Registry, every producer-consumer pair must agree on message format out-of-band — through documentation, convention, or synchronized deploys. With it, schema evolution is governed: you can add nullable fields (backward-compatible), remove old fields (forward-compatible), or enforce full compatibility, all with automatic enforcement.

**Real-world scenario — HDFC Bank payment event schema evolution:**

The `payment.processed` topic is consumed by 14 downstream services. Six months in, the risk team needs to add a `deviceFingerprint` field to every payment event. Without Schema Registry this requires coordinating a simultaneous deploy of all 14 consumers. With Schema Registry using `BACKWARD` compatibility mode:

1. The payments team registers `PaymentEvent v2` — with `deviceFingerprint` as an optional field with a null default.
2. Schema Registry validates the new schema is backward-compatible with v1.
3. The payments producer deploys and starts writing v2 events.
4. All 14 existing consumers continue reading without any code changes — the new field is populated with the default when absent.
5. Consumer teams adopt v2 at their own pace over the following sprint.

```bash
# Register a schema
curl -X POST http://localhost:8081/subjects/payment.processed-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"PaymentEvent\",\"fields\":[{\"name\":\"amount\",\"type\":\"double\"},{\"name\":\"deviceFingerprint\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'

# Check compatibility before deploying a schema change
curl -X POST http://localhost:8081/compatibility/subjects/payment.processed-value/versions/latest \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "..."}'
```

---

### Kafka Connect

**What it is:** A scalable, fault-tolerant framework for streaming data into Kafka from external systems (source connectors) and out of Kafka into external systems (sink connectors). Instead of writing custom glue code, you POST a JSON configuration to the Connect REST API and it handles everything else — partitioning, parallelism, offset tracking, restarts on failure.

**Connectors available from the Confluent Hub (100+):**
- **Sources:** Debezium PostgreSQL/MySQL/MongoDB CDC, JDBC, S3, HTTP, Salesforce
- **Sinks:** Elasticsearch, S3, Google BigQuery, Snowflake, JDBC, Redis, HTTP

**Real-world scenario — OLA ride CDC pipeline:**

OLA's PostgreSQL `rides` table is the source of truth for ongoing rides. The analytics team needs every INSERT, UPDATE, and DELETE streamed into Kafka in real time — without modifying the rides API service. They deploy a Debezium PostgreSQL connector via the REST API:

```json
POST http://localhost:8083/connectors
{
  "name": "postgres-rides-cdc",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "dbz",
    "database.dbname": "oladb",
    "table.include.list": "public.rides",
    "topic.prefix": "ola",
    "plugin.name": "pgoutput"
  }
}
```

Every ride status change — `REQUESTED → DRIVER_ASSIGNED → IN_PROGRESS → COMPLETED` — now flows as a Kafka event. The fraud detection model, the driver earnings service, and the surge-pricing calculator each subscribe independently from the same CDC stream, with zero modifications to the rides API codebase.

```bash
# Install Debezium into the running Connect container
docker exec kafka-connect \
  confluent-hub install debezium/debezium-connector-postgresql:latest \
  --component-dir /usr/share/confluent-hub-components \
  --no-prompt

# Restart Connect to pick up the new plugin
docker compose restart kafka-connect
```

---

### REST Proxy

**What it is:** An HTTP API wrapper around the Kafka protocol. Any HTTP client — curl, a browser, an IoT device, a legacy service without a Kafka SDK — can produce and consume messages by making standard REST calls. The proxy translates HTTP requests into native Kafka protocol and handles all the client-side complexity.

**When to use it:**
- Legacy services that cannot adopt a native Kafka client library
- IoT or embedded devices where the full Kafka SDK is impractical
- Quick integration tests without writing dedicated consumer code
- Languages or environments without a mature Kafka client

**Real-world scenario — CRED POS terminal network:**

CRED deploys point-of-sale card reader terminals at merchant locations. These terminals run minimal embedded firmware and can only make HTTP POST requests — they cannot embed a JVM or native Kafka client. The REST Proxy allows them to publish payment events directly over HTTP:

```bash
# Terminal produces a payment event via plain HTTP
curl -X POST http://kafka-restproxy.internal/topics/payments \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{
    "records": [{
      "key": "terminal_MUM_4821",
      "value": {
        "amount": 2499.00,
        "merchantId": "M_BANDRA_042",
        "cardLast4": "8821",
        "timestamp": "2024-03-15T14:32:00Z"
      }
    }]
  }'
```

The REST Proxy serializes the HTTP payload into a native Kafka `ProducerRecord` and writes it to the `payments` topic. The fraud detection service and settlement service read from Kafka normally — completely unaware the event originated from an HTTP call.

---

### Control Center

**What it is:** Confluent's enterprise-grade web UI for monitoring and managing the full Kafka ecosystem. It provides real-time consumer lag graphs, per-broker and per-topic throughput charts, partition assignment views, alerting rules, ACL management, and the ability to inspect messages through the browser.

**Real-world scenario — Meesho ops team during a GMV push event:**

During a sale event, Meesho's on-call engineer has Control Center open on a dashboard monitor. At 2:14 PM, consumer lag on the `order.created` topic spikes from 0 to 50,000 messages — the downstream fulfillment service is falling behind. Control Center's lag graph fires a PagerDuty alert within 30 seconds. The engineer opens the consumer group health view, sees that 2 of 6 fulfillment consumer pods show no partition assignments (they've crashed), scales the deployment from 6 to 10 pods, and watches the lag drain to zero in 90 seconds. The entire incident is resolved before any customer-visible SLA breach.

```
Open browser → http://localhost:9021
```

> Control Center takes 2–3 minutes to populate metrics after first startup due to Confluent metrics topic initialization.

---

### Kafka UI (Provectus)

**What it is:** A lightweight, open-source alternative to Control Center for everyday development work. No enterprise license required. It offers topic browsing, live message inspection with filters, consumer group lag visibility, Schema Registry integration, and Kafka Connect management — all in a fast single-page app.

**Real-world scenario — Backend developer debugging a serialization bug at Razorpay:**

A developer pushes a new version of the `refund.initiated` producer. A bug in the Avro serializer means some events are missing the `refundReasonCode` field. Before the issue reaches QA, the developer opens Kafka UI at `http://localhost:8080`:

1. Selects the `refund.initiated` topic
2. Clicks **Messages** → filters to the last 50 offsets
3. Inspects the raw JSON payload in the browser — the missing field is immediately visible
4. Fixes the serializer and re-runs the producer
5. Confirms the next batch of messages contains the field correctly

The complete debug cycle takes three minutes. No CLI access, no asking the platform team for credentials, no grepping log files.

```
Open browser → http://localhost:8080
```

---

## Real-World Data Flow: E-Commerce Order Pipeline

How all the components work together when a customer places an order:

```
Customer places order
        │
        ▼
┌─────────────────┐   Schema Registry validates   ┌───────────────────────────┐
│  Order Service  │ ─── OrderPlaced Avro schema ─► │      Kafka Broker         │
│  (Producer)     │                                │                           │
└─────────────────┘                                │  topic: orders            │
                                                   │  topic: payments          │
┌─────────────────┐                                │  topic: inventory.updated │
│ Payment Service │ ───────────────────────────►   │  topic: user.events       │
└─────────────────┘                                └──────────────┬────────────┘
                                                                   │
      ┌────────────────────────────────────────────────────────────┤
      │                │                    │                      │
      ▼                ▼                    ▼                      ▼
┌──────────────┐ ┌───────────────┐ ┌──────────────┐  ┌───────────────────┐
│ Email Service│ │    Fraud      │ │  Analytics   │  │  Warehouse Svc    │
│              │ │  Detection    │ │  (BigQuery)  │  │  (fulfillment)    │
│ Sends order  │ │  ML scoring   │ │              │  │                   │
│ confirmation │ │ flags risky   │ │ updates sale │  │ reserves stock    │
│ via SES      │ │ transactions  │ │ dashboards   │  │ triggers dispatch │
└──────────────┘ └───────────────┘ └──────────────┘  └───────────────────┘
```

**Why this architecture is powerful:**

- **Decoupling:** Order Service has zero knowledge of Email Service or Fraud Detection. It publishes to a topic. Everything else is downstream.
- **Independent scaling:** During a flash sale, the Analytics consumer can fall 2 hours behind without slowing order processing or email delivery by a single millisecond.
- **Fault-tolerant replay:** If the Warehouse Service has a 2-hour outage, it reconnects and replays all missed events. No orders are lost, no manual reconciliation needed.
- **Fan-out:** One order event is consumed independently by all four services at their own pace, with no coordination required between them.
- **Schema evolution:** As the order schema evolves over months, Schema Registry enforces compatibility so no consumer breaks unexpectedly.

---

## Port Reference

| Service          | URL                          | What you can do there                               |
|------------------|------------------------------|-----------------------------------------------------|
| Kafka UI         | http://localhost:8080        | Browse topics, messages, consumer groups, schemas   |
| Schema Registry  | http://localhost:8081        | REST API — list subjects, register and check schemas |
| REST Proxy       | http://localhost:8082        | Produce and consume messages via plain HTTP         |
| Kafka Connect    | http://localhost:8083        | Deploy, configure, and monitor connectors           |
| Control Center   | http://localhost:9021        | Enterprise monitoring, lag graphs, alerting         |
| Kafka Broker     | localhost:29092              | Bootstrap server for host machine applications      |
| Kafka Broker     | kafka:9092                   | Bootstrap server from within the Docker network     |
| Zookeeper        | localhost:2181               | Direct ZK access (rarely needed)                    |

---

## Quick Start

### Prerequisites

```bash
docker --version        # 20.10+
docker compose version  # v2.0+
```

### 1. Prepare directory structure

```
.
├── docker-compose.yml
├── Makefile
└── connect-plugins/    ← required even if empty
```

```bash
mkdir -p connect-plugins
```

### 2. Start the stack

```bash
make up
# or
docker compose up -d
```

Services start in dependency-ordered sequence enforced by health checks:

```
Zookeeper       (health: echo ruok)
    └─► Kafka Broker    (health: kafka-broker-api-versions)
            ├─► Schema Registry  (health: curl /subjects)
            ├─► Kafka Connect    (health: curl /)
            ├─► REST Proxy
            ├─► Control Center
            └─► Kafka UI
```

Allow **60–90 seconds** for the full stack to become healthy:

```bash
make ps       # see container states
make health   # check each service
```

---

## Common Operations

### Topics

```bash
make create-topic TOPIC=orders PARTITIONS=6
make list-topics
make describe-topic TOPIC=orders
make delete-topic TOPIC=orders
```

### Produce and consume

```bash
# Interactive producer — type a message per line, Ctrl+C to exit
make produce TOPIC=orders

# Consume all messages from the beginning
make consume TOPIC=orders

# Consume as a named group (offset is tracked and committed)
make consume-group TOPIC=orders GROUP=order-processor
```

### Consumer group management

```bash
make list-groups
make describe-group GROUP=order-processor
```

### Schema Registry

```bash
make list-schemas

# Register a schema
curl -X POST http://localhost:8081/subjects/orders-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Order\",\"fields\":[{\"name\":\"orderId\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"}]}"}'
```

### Kafka Connect

```bash
make list-connectors

# Deploy the Debezium PostgreSQL CDC connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connector-config.json

make connector-status CONNECTOR=postgres-rides-cdc
```

---

## Connecting Your Application

### From your host machine

```
bootstrap.servers  = localhost:29092
schema.registry.url = http://localhost:8081
```

### From another container on the same Docker network

```
bootstrap.servers  = kafka:9092
schema.registry.url = http://schema-registry:8081
```

Add your service to the network in your own `docker-compose.yml`:

```yaml
services:
  my-service:
    networks:
      - kafka-network

networks:
  kafka-network:
    external: true
    name: kafka-network
```

### Python (confluent-kafka)

```python
from confluent_kafka import Producer, Consumer

producer = Producer({"bootstrap.servers": "localhost:29092"})
producer.produce("orders", key="ord_001", value='{"amount": 1299}')
producer.flush()

consumer = Consumer({
    "bootstrap.servers": "localhost:29092",
    "group.id": "order-processor",
    "auto.offset.reset": "earliest",
})
consumer.subscribe(["orders"])
msg = consumer.poll(timeout=5.0)
print(msg.value())
```

### Node.js (kafkajs)

```javascript
const { Kafka } = require("kafkajs");
const kafka = new Kafka({ brokers: ["localhost:29092"] });

const producer = kafka.producer();
await producer.connect();
await producer.send({
  topic: "orders",
  messages: [{ key: "ord_001", value: JSON.stringify({ amount: 1299 }) }],
});
await producer.disconnect();
```

### Java (Spring Boot)

```yaml
# application.yml
spring:
  kafka:
    bootstrap-servers: localhost:29092
    consumer:
      group-id: order-processor
      auto-offset-reset: earliest
```

```java
@KafkaListener(topics = "orders", groupId = "order-processor")
public void consume(String message) {
    System.out.println("Order received: " + message);
}
```

---

## Tear Down

```bash
make down      # stop containers, volumes preserved
make destroy   # stop containers and delete all data volumes
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Kafka UI shows "Failed to connect" | Broker not ready yet | Wait 90 s, refresh — health checks enforce startup order |
| `LEADER_NOT_AVAILABLE` on produce | Topic just created | Retry in 1–2 s, leader election is still running |
| Host app can't reach broker | Wrong address | Use `localhost:29092`, not `kafka:9092` |
| Container app can't reach broker | Wrong address | Use `kafka:9092` from within the Docker network |
| Control Center shows no metrics | Normal on first startup | Takes 2–3 min for metrics topics to initialize |
| Connect plugin not found | Plugin not installed | Run `confluent-hub install` then restart `kafka-connect` |
| Messages not consumed | Group already committed offset | Reset: `kafka-consumer-groups --reset-offsets --to-earliest` |
| Schema registration returns 409 | Compatibility conflict | Check `GET /config/{subject}` and adjust compatibility level |
| `replication.factor > live brokers` | Single-broker setup | Max replication factor is 1 in this single-node stack |

---

## Production Considerations

This setup is configured for local development. Before going to production:

- **Replication:** Set `replication.factor: 3` (minimum) across three broker nodes for fault tolerance.
- **Topic governance:** Disable `AUTO_CREATE_TOPICS_ENABLE` and manage topics explicitly with Terraform or the Confluent Operator.
- **Security:** Replace `PLAINTEXT` listeners with `SASL_SSL`, add mTLS between services, configure ACLs per consumer group.
- **JVM tuning:** Set `KAFKA_HEAP_OPTS` appropriately for your broker instance class (typically `-Xmx6g -Xms6g` for 8 GB nodes).
- **Tiered storage:** Configure S3 or GCS as a log tier for cost-effective long-term message retention.
- **Schema Registry HA:** Run at least two Schema Registry instances behind a load balancer.
- **KRaft mode:** For new production deployments on Confluent 7.4+, use KRaft (Kafka Raft) to eliminate the Zookeeper dependency entirely.

---

## Resources

- [Confluent Platform Documentation](https://docs.confluent.io/platform/current/)
- [Kafka UI — Provectus (GitHub)](https://github.com/provectus/kafka-ui)
- [Debezium CDC Connectors](https://debezium.io/documentation/)
- [Confluent Hub — connector catalog](https://www.confluent.io/hub/)
- [kafkajs — Node.js client](https://kafka.js.org/)
- [confluent-kafka-python](https://docs.confluent.io/kafka-clients/python/current/overview.html)
- [Spring for Apache Kafka](https://spring.io/projects/spring-kafka)
