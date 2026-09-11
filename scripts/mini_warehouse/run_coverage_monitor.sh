#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"

OUTPUT_DIR="${1:-$ROOT/results/mini_warehouse/smoke/coverage_monitor}"

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
set -u

exec python3 \
    "$ROOT/experiments/scripts/mini_warehouse/coverage_monitor.py" \
    --output-dir "$OUTPUT_DIR" \
    --resolution 0.05 \
    --map-size-m 20.0 \
    --max-ray-range-m 12.0 \
    --process-period-sec 0.5 \
    --publish-period-sec 2.0 \
    --snapshot-period-sec 30.0
