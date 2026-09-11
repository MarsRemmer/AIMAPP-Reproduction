#!/usr/bin/env bash
set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"

OUTPUT_DIR="${1:-$ROOT/results/mini_warehouse/validation/coverage_manual}"

COVERAGE_RESOLUTION_M="${COVERAGE_RESOLUTION_M:-0.05}"
COVERAGE_MAP_SIZE_M="${COVERAGE_MAP_SIZE_M:-40.0}"
COVERAGE_MAX_RAY_RANGE_M="${COVERAGE_MAX_RAY_RANGE_M:-12.0}"
COVERAGE_PROCESS_PERIOD_SEC="${COVERAGE_PROCESS_PERIOD_SEC:-0.5}"
COVERAGE_PUBLISH_PERIOD_SEC="${COVERAGE_PUBLISH_PERIOD_SEC:-2.0}"
COVERAGE_SNAPSHOT_PERIOD_SEC="${COVERAGE_SNAPSHOT_PERIOD_SEC:-30.0}"

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
set -u

exec python3     "$ROOT/experiments/scripts/mini_warehouse/coverage_monitor.py"     --output-dir "$OUTPUT_DIR"     --resolution "$COVERAGE_RESOLUTION_M"     --map-size-m "$COVERAGE_MAP_SIZE_M"     --max-ray-range-m "$COVERAGE_MAX_RAY_RANGE_M"     --process-period-sec "$COVERAGE_PROCESS_PERIOD_SEC"     --publish-period-sec "$COVERAGE_PUBLISH_PERIOD_SEC"     --snapshot-period-sec "$COVERAGE_SNAPSHOT_PERIOD_SEC"
