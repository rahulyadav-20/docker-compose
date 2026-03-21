#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — Start the Apache Druid cluster
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     Apache Druid Docker Stack Setup      ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# Create shared directories
echo -e "${YELLOW}→ Creating shared data directories...${RESET}"
mkdir -p ./data/shared/segments
mkdir -p ./data/shared/indexing-logs
mkdir -p ./data/shared/tmp
chmod -R 777 ./data

echo -e "${YELLOW}→ Pulling Docker images...${RESET}"
docker compose pull

echo -e "${YELLOW}→ Starting infrastructure (ZooKeeper + PostgreSQL)...${RESET}"
docker compose up -d zookeeper postgres

echo -e "${YELLOW}→ Waiting for infrastructure to be healthy...${RESET}"
sleep 15

echo -e "${YELLOW}→ Starting Druid master services...${RESET}"
docker compose up -d coordinator overlord

echo -e "${YELLOW}→ Waiting for master services...${RESET}"
sleep 20

echo -e "${YELLOW}→ Starting Druid data & query services...${RESET}"
docker compose up -d historical middlemanager broker

echo -e "${YELLOW}→ Waiting for data services...${RESET}"
sleep 20

echo -e "${YELLOW}→ Starting Router (Web UI)...${RESET}"
docker compose up -d router

echo ""
echo -e "${GREEN}${BOLD}✓ Druid cluster is starting up!${RESET}"
echo ""
echo -e "  ${BOLD}Druid Console (UI):${RESET}    http://localhost:${BOLD}8888${RESET}"
echo -e "  ${BOLD}Coordinator API:${RESET}        http://localhost:8081"
echo -e "  ${BOLD}Overlord API:${RESET}           http://localhost:8090"
echo -e "  ${BOLD}Broker API:${RESET}             http://localhost:8082"
echo -e "  ${BOLD}Historical API:${RESET}         http://localhost:8083"
echo -e "  ${BOLD}MiddleManager API:${RESET}      http://localhost:8091"
echo ""
echo -e "${YELLOW}Note: Full startup takes 1-2 minutes. Watch logs with:${RESET}"
echo -e "  docker compose logs -f router"
echo ""