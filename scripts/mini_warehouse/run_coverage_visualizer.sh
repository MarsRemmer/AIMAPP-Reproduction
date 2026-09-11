#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"

OUTPUT_DIR="${1:-$ROOT/results/mini_warehouse/coverage_visualization}"

SHOW="${SHOW:-0}"

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
set -u

ARGS=(
    --output-dir "$OUTPUT_DIR"
    --frame-period-sec 1.0
    --video-fps 8.0
    --image-scale 2
)

if [[ "$SHOW" == "1" ]]; then
    ARGS+=(
        --display
    )
fi

exec python3 \
    "$ROOT/experiments/scripts/mini_warehouse/coverage_visualizer.py" \
    "${ARGS[@]}"
