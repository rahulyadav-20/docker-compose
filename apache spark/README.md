# Apache Spark on Docker 🔥

> A fully functional Apache Spark 3.5.0 cluster using the official `apache/spark` image — with Master, 3 Workers, History Server, and Jupyter Lab, all wired together via Docker Compose.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Ports & Web UIs](#ports--web-uis)
- [Quick Start](#quick-start)
- [Job Execution Lifecycle](#job-execution-lifecycle)
- [Real-World Scenarios](#real-world-scenarios)
- [Configuration Reference](#configuration-reference)
- [Quick Command Reference](#quick-command-reference)
- [Spark Shells](#spark-shells)
- [Troubleshooting](#troubleshooting)

---

## Overview

This setup mirrors a real production Spark cluster on your laptop — no cloud spend, no dependency conflicts, instant teardown. It behaves identically to AWS EMR, Google Dataproc, or Azure HDInsight in terms of cluster topology and job submission.

**What you get:**
- Spark Master managing resource allocation
- 3 independent Workers each with 2 cores / 2 GB RAM (6 total cores)
- History Server for post-mortem job inspection
- Jupyter Lab for interactive PySpark exploration
- Shared volumes so job outputs are immediately accessible on your host machine

---

## Architecture

```
  ┌─────────────────────────────────────────────────────────────┐
  │                  Docker Network: spark-net                   │
  │                                                             │
  │              ┌───────────────────────────────┐              │
  │              │         Spark Master          │              │
  │              │   :7077 (cluster) :8080 (UI)  │              │
  │              └──────────┬──────┬─────────────┘              │
  │                    ┌────┘      └────┐                        │
  │         ┌──────────┴──┐    ┌───────┴────┐  ┌────────────┐  │
  │         │  Worker 1   │    │  Worker 2  │  │  Worker 3  │  │
  │         │   :8081     │    │   :8082    │  │   :8083    │  │
  │         └─────────────┘    └────────────┘  └────────────┘  │
  │                                                             │
  │    ┌──────────────────────┐   ┌──────────────────────────┐  │
  │    │    History Server    │   │       Jupyter Lab        │  │
  │    │       :18080         │   │         :8888            │  │
  │    └──────────────────────┘   └──────────────────────────┘  │
  │                                                             │
  │         Shared Volumes: ./data   ./logs   ./apps            │
  └─────────────────────────────────────────────────────────────┘
```

### Network Topology

All containers join a single Docker bridge network (`spark-net`). Containers resolve each other by hostname — `spark-master`, `spark-worker-1`, etc. — so no IP addresses are hardcoded. If a container restarts, hostname resolution still works.

### Shared Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./data` | `/opt/spark/data` | Input datasets and job output (Parquet, CSV, Delta) |
| `./logs` | `/opt/spark/logs` | Spark event logs, read by the History Server |
| `./apps` | `/opt/spark/apps` | PySpark / Scala scripts for `spark-submit` |

> **Key insight:** Because all containers share `./data`, a job running on `worker-3` can write a Parquet file that you immediately open in pandas on your laptop — no copying, no SSH needed.

---

## Components

| Component | Role in Cluster | Real-World Scenario |
|---|---|---|
| **Spark Master** | Manages the cluster. Accepts job submissions, tracks worker resources, assigns executors. | An e-commerce platform's nightly ETL pipeline submits jobs here. The master decides which workers run each stage. |
| **Spark Worker 1–3** | Each worker hosts executors that perform actual data processing in parallel JVM processes. | A financial firm runs fraud-detection models across 3 workers simultaneously — each crunches a shard of transaction data. |
| **History Server** | Stores event logs from completed apps. Lets you inspect past jobs, DAGs, and metrics post-mortem. | A data team debugs why a batch job was slow last Tuesday by replaying its full execution timeline. |
| **Jupyter Lab** | Browser-based Python notebook. Connects to the cluster for interactive data exploration. | A data scientist explores a new dataset interactively before packaging logic into a production `spark-submit` job. |
| **Shared Volume `./data`** | A host directory mounted in all containers, enabling jobs to read inputs and write outputs accessible from your machine. | A pipeline writes Parquet results to `./data/output` and an analyst opens them locally in pandas without copying files. |
| **Shared Volume `./logs`** | Event log directory written by every service and read by the History Server. | DevOps reviews job metrics from the History Server UI without SSH-ing into any container. |
| **Docker Network** | Bridge network isolating the cluster. Containers resolve each other by hostname. | Workers join the master using `spark://spark-master:7077` — no IP addresses needed, survives container restarts. |

---

## Ports & Web UIs

| Service | Container | Host Port | Purpose |
|---|---|---|---|
| Spark Master UI | `spark-master` | **8080** | View cluster status, active workers, running apps |
| Cluster Connect | `spark-master` | **7077** | Workers & drivers register here |
| App UI (live) | `spark-master` | **4040** | Real-time DAG, stages, tasks for running apps |
| Worker 1 UI | `spark-worker-1` | **8081** | Executor logs, resource usage |
| Worker 2 UI | `spark-worker-2` | **8082** | Executor logs, resource usage |
| Worker 3 UI | `spark-worker-3` | **8083** | Executor logs, resource usage |
| History Server | `spark-history` | **18080** | Completed app logs, DAG replay, metrics |
| Jupyter Lab | `spark-jupyter` | **8888** | Interactive PySpark notebook environment |

> **Note:** Port `4040` is only active while a Spark application is running. Open it immediately after submitting a job to watch stages execute in real time. Once the job finishes, use the History Server on `18080` instead.

---

## Quick Start

### Prerequisites

- Docker ≥ 24.x
- Docker Compose ≥ 2.x
- ~8 GB RAM free (cluster uses ~6 GB)

### Start the cluster

```bash
# Start everything (pulls apache/spark:3.5.0 on first run)
make up

# or without Make:
docker compose up -d
```

Wait ~30 seconds, then open the Spark Master UI:

```
http://localhost:8080
```

You should see **3 workers** registered and alive.

### Run the sample job

```bash
make submit
```

This runs `apps/sample_job.py` which demonstrates:
- **Monte Carlo π estimation** — RDD API, distributed computation
- **DataFrame aggregations** — `groupBy`, `avg`, `max`, Parquet output
- **Spark SQL** — temp views, SQL queries on distributed data

Watch it live at `http://localhost:4040` while running, then replay it at `http://localhost:18080` after it finishes.

---

## Job Execution Lifecycle

What happens from `spark-submit` to result file:

| Step | Stage | What happens |
|---|---|---|
| 1 | **Job submission** | `spark-submit` sends the driver program to the master via port 7077 |
| 2 | **Resource negotiation** | Master inspects available cores/memory across workers and grants executor slots |
| 3 | **Executor launch** | Workers spawn JVM executor processes and register back to the driver |
| 4 | **DAG construction** | Driver breaks your Spark code into a DAG of stages and tasks |
| 5 | **Task dispatch** | Driver sends individual tasks to executors; data is read from the shared volume |
| 6 | **Shuffle** | Wide transformations (`groupBy`, `join`) cause executors to exchange partitions across workers |
| 7 | **Output write** | Final RDD or DataFrame is written to `./data/output` as Parquet/CSV/Delta |
| 8 | **Event logging** | Throughout the job, events stream to `./logs`; the History Server indexes them |

### Stages and Tasks

Spark converts your DataFrame or RDD transformations into a **Directed Acyclic Graph (DAG)** of stages. Each stage is a set of tasks that can run in parallel without shuffling data. A shuffle boundary (caused by `groupBy`, `join`, `distinct`, etc.) always creates a new stage.

With 3 workers × 2 cores = **6 parallel tasks maximum**. The default shuffle partition count is set to `6` in `spark-defaults.conf` to match available parallelism.

### Fault Tolerance

If an executor fails mid-job, the driver detects the failure and re-schedules its tasks on a healthy executor automatically — no data is lost because Spark tracks which partitions each task processed. If a worker container crashes, the master marks it dead and reassigns its work to remaining workers.

---

## Real-World Scenarios

| Industry | Use Case | Spark Pattern | Components Used |
|---|---|---|---|
| E-Commerce | Nightly sales ETL | Batch: read CSV → aggregate → write Parquet | Master, 3 Workers, History Server |
| Finance | Real-time fraud detection | Structured Streaming on Kafka topic | Master, Workers, App UI (4040) |
| Healthcare | Patient cohort analysis | DataFrame joins across 10+ tables | Workers (heavy shuffle), Jupyter |
| Media | Recommendation engine | ALS collaborative filtering (MLlib) | All workers, Jupyter for tuning |
| Logistics | Route optimisation | GraphX / Pregel for shortest-path | Master, Workers, History replay |
| Data Science | Feature engineering | Interactive pandas-on-Spark exploration | Jupyter Lab + PySpark REPL |

### Nightly ETL Pipeline (E-Commerce)

A retailer runs a nightly job at 02:00 that reads 50 GB of raw clickstream CSV files, joins them with a product catalogue, aggregates revenue by SKU and region, and writes the result as Parquet.

```bash
docker exec spark-master spark-submit \
  --master spark://spark-master:7077 \
  --executor-memory 1G \
  --total-executor-cores 6 \
  /opt/spark/apps/nightly_etl.py
```

While the job runs, the **Stages** tab on `localhost:4040` shows each aggregation stage, shuffle read/write sizes, and per-task duration. After completion, the same view is available on the History Server.

### Streaming Fraud Detection (Finance)

A bank uses Spark Structured Streaming to consume a Kafka topic of card transactions and apply a pre-trained MLlib model to flag suspicious activity within 2 seconds.

```python
df = (spark.readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", "kafka:9092")
        .option("subscribe", "transactions")
        .load())

scored = model.transform(df)

scored.writeStream.format("console").start().awaitTermination()
```

The History Server retains each micro-batch as a completed query, giving compliance teams a full audit trail of which batches ran, how long they took, and how many records were processed.

### Interactive Data Exploration (Data Science)

A data scientist opens Jupyter Lab on `localhost:8888` and connects to the cluster:

```python
from pyspark.sql import SparkSession

spark = (SparkSession.builder
           .master("spark://spark-master:7077")
           .appName("Exploration")
           .getOrCreate())

df = spark.read.parquet("/home/jovyan/data/sales.parquet")
df.groupBy("category").agg({"revenue": "sum"}).show()
```

They iterate in seconds on the full dataset, then paste the final logic into a `.py` script and run it via `spark-submit` for a full production run.

---

## Configuration Reference

### spark-defaults.conf

Mounted to `/opt/spark/conf/spark-defaults.conf` in every container.

| Property | Value | Why |
|---|---|---|
| `spark.eventLog.enabled` | `true` | Required for the History Server to index completed jobs |
| `spark.serializer` | `KryoSerializer` | Faster and more compact than Java serialization |
| `spark.sql.adaptive.enabled` | `true` | AQE coalesces small shuffle partitions, handles skew, picks better joins at runtime |
| `spark.default.parallelism` | `6` | Matches total cores (3 workers × 2). Too low wastes capacity; too high adds overhead |
| `spark.sql.shuffle.partitions` | `6` | Default 200 is far too high for a small local cluster |
| `spark.executor.memory` | `1500m` | Leaves headroom for JVM overhead on top of the 2 GB worker limit |
| `spark.network.timeout` | `800s` | Prevents false-positive executor loss during long GC pauses or heavy shuffles |
| `spark.driver.memory` | `1g` | Memory for the driver process (runs on master) |

### Scaling Workers

To run more parallel tasks, edit `docker-compose.yml`:

```yaml
environment:
  - SPARK_WORKER_MEMORY=4G
  - SPARK_WORKER_CORES=4
```

Then update `spark-defaults.conf` to match:

```
spark.default.parallelism       12   # 3 workers × 4 cores
spark.sql.shuffle.partitions    12
```

---

## Quick Command Reference

### Cluster lifecycle

```bash
make up           # Pull apache/spark and start the full cluster
make down         # Stop and remove containers
make status       # Show container health
make logs         # Tail all logs
make logs-master  # Master logs only
make restart      # Restart all services
make clean        # Remove containers, volumes, and generated data
```

### Job submission

```bash
make submit                         # Run apps/sample_job.py
make submit-custom SCRIPT=apps/x    # Run a custom script
```

Manual submission:

```bash
docker exec spark-master spark-submit \
  --master spark://spark-master:7077 \
  --executor-memory 1G \
  --total-executor-cores 6 \
  /opt/spark/apps/your_job.py
```

---

## Spark Shells

```bash
# Scala shell
docker exec -it spark-master /opt/spark/bin/spark-shell \
  --master spark://spark-master:7077

# Python shell
docker exec -it spark-master /opt/spark/bin/pyspark \
  --master spark://spark-master:7077

# SQL shell
docker exec -it spark-master /opt/spark/bin/spark-sql \
  --master spark://spark-master:7077
```

Or use the Makefile shortcuts:

```bash
make pyspark     # PySpark REPL
make spark-sql   # SQL shell
make shell       # Bash on master
```

Quick test once inside the shell:

```python
# PySpark
rdd = sc.parallelize(range(1, 101))
rdd.filter(lambda x: x % 2 == 0).count()  # → 50
```

```scala
// Scala spark-shell
val rdd = sc.parallelize(1 to 100)
rdd.filter(_ % 2 == 0).count()  // → 50
```

The live **Application UI** appears at `http://localhost:4040` while the shell session is open.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Worker not showing in Master UI | Run `make logs` to check worker startup. `spark-master` must pass its health check before workers start. |
| Port 8080 already in use | Stop any existing service on 8080, or change the host port in `docker-compose.yml` (left side of the colon). |
| Job fails with `OutOfMemoryError` | Reduce `spark.sql.shuffle.partitions`, increase `SPARK_WORKER_MEMORY`, or lower `--executor-memory` to leave JVM overhead room. |
| History Server shows no applications | Check `spark.eventLog.enabled=true` in `spark-defaults.conf` and that `./logs` is writable by uid `185`. |
| Port 4040 not reachable | 4040 is only active while a job is running. Submit a job first, then open the URL. |
| Jupyter can't connect to master | Verify the `jupyter` service has `networks: spark-net` in `docker-compose.yml`. |

**Clean restart** if the cluster gets into a bad state:

```bash
make clean && make up
```

---

## Directory Structure

```
spark-docker/
├── docker-compose.yml          # Cluster definition
├── Makefile                    # Convenience commands
├── README.md                   # This file
├── conf/
│   └── spark-defaults.conf     # Shared Spark config (mounted into all containers)
├── apps/
│   └── sample_job.py           # Example PySpark job
├── notebooks/
│   └── pyspark_demo.ipynb      # Jupyter notebook
├── data/                       # Input/output data (shared across all containers)
└── logs/                       # Spark event logs (read by History Server)
```