#!/usr/bin/env bash

# Common Mini Warehouse experiment recorder.
#
# The SAME recorder is used for:
#   AIMAPP + Nav2
#   SCA baseline + Nav2
#
# Start this recorder BEFORE A5.
# rosbag topic discovery remains enabled so experiment topics that appear
# after the algorithm starts are added automatically.

set -eo pipefail

export PYTHONDONTWRITEBYTECODE=1

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

set -u

START_X="${START_X:-0.0}"
START_Y="${START_Y:-0.0}"
START_YAW="${START_YAW:-0.0}"

export START_X
export START_Y
export START_YAW

METHOD="${1:-}"
RUN_NAME="${2:-run_$(date +%Y%m%d_%H%M%S)}"
MODE="${3:-}"

if [[ -z "$METHOD" ]]; then
    echo "Usage:"
    echo "  $0 <method> [run_name] [--check]"
    echo
    echo "Examples:"
    echo "  $0 aimapp_nav2 run_001"
    echo "  $0 sca_baseline_nav2 run_001"
    exit 1
fi

PROJECT_ROOT="$HOME/SCA-AIFNav-Project"

START_X="${START_X:-0.0}"
START_Y="${START_Y:-0.0}"
START_YAW="${START_YAW:-0.0}"

COVERAGE_SEMANTICS="${COVERAGE_SEMANTICS:-ever_observed_lidar_cells}"
COVERAGE_RESOLUTION_M="${COVERAGE_RESOLUTION_M:-0.05}"
COVERAGE_MAP_SIZE_M="${COVERAGE_MAP_SIZE_M:-40.0}"
COVERAGE_MAX_RAY_RANGE_M="${COVERAGE_MAX_RAY_RANGE_M:-12.0}"

export COVERAGE_SEMANTICS
export COVERAGE_RESOLUTION_M
export COVERAGE_MAP_SIZE_M
export COVERAGE_MAX_RAY_RANGE_M

if [[ "$MODE" == "--check" ]]; then
    RESULT_ROOT="$PROJECT_ROOT/results/mini_warehouse/smoke"
else
    RESULT_ROOT="$PROJECT_ROOT/results/mini_warehouse/formal"
fi

RUN_DIR="$RESULT_ROOT/$METHOD/$RUN_NAME"

mkdir -p "$RUN_DIR"

# ----------------------------------------------------------------------
# Only experiment-relevant topics are recorded.
#
# Important:
# rosbag discovery remains active. Therefore topics such as
# /visitable_nodes or /sca_aifnav/... may appear only after A5 starts
# and will still be recorded.
# ----------------------------------------------------------------------

TOPIC_REGEX='^/(clock|odom|agent/odom|scan|cmd_vel|tf|tf_static|initialpose|amcl_pose|map|plan|visitable_nodes|node_connections|sca_aifnav/.*|experiment/.*|navigate_to_pose/_action/(feedback|status))$'

echo "============================================================"
echo "Mini Warehouse Common Recorder"
echo "============================================================"
echo "Method : $METHOD"
echo "Run    : $RUN_NAME"
echo "Output : $RUN_DIR"
echo
echo "Topic regex:"
echo "$TOPIC_REGEX"
echo

git_sha_or_unknown()
{
    local repo="$1"

    if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
        git -C "$repo" rev-parse HEAD
    else
        echo "unknown"
    fi
}

EXPERIMENT_HARNESS_COMMIT="$(
    git_sha_or_unknown \
    "$PROJECT_ROOT/experiments"
)"

AIMAPP_RUNTIME_COMMIT="$(
    git_sha_or_unknown \
    "$PROJECT_ROOT/aimapp/runtime_ws/src/aimapp"
)"

SCA_COMMIT="$(
    git_sha_or_unknown \
    "$PROJECT_ROOT/sca_aifnav/runtime_ws/src/sca_aifnav"
)"

export METHOD
export RUN_NAME
export RUN_DIR
export TOPIC_REGEX
export START_X
export START_Y
export START_YAW
export EXPERIMENT_HARNESS_COMMIT
export AIMAPP_RUNTIME_COMMIT
export SCA_COMMIT

python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

run_dir = Path(os.environ["RUN_DIR"])

metadata = {
    "schema_version": 3,
    "method": os.environ["METHOD"],
    "run_name": os.environ["RUN_NAME"],
    "world": "mini_warehouse",
    "robot": "waffle_pi_plus",
    "motion_backend": "nav2",
    "start_pose": {
        "x": float(os.environ["START_X"]),
        "y": float(os.environ["START_Y"]),
        "yaw_rad": float(os.environ["START_YAW"]),
    },
    "baseline_influence_radius_m": 0.5,
    "coverage_evaluation": {
        "semantics": os.environ["COVERAGE_SEMANTICS"],
        "resolution_m": float(os.environ["COVERAGE_RESOLUTION_M"]),
        "map_size_m": float(os.environ["COVERAGE_MAP_SIZE_M"]),
        "max_ray_range_m": float(os.environ["COVERAGE_MAX_RAY_RANGE_M"]),
    },
    "started_at_utc": datetime.now(
        timezone.utc
    ).isoformat(),
    "rosbag_topic_regex": (
        os.environ["TOPIC_REGEX"]
    ),
    "git": {
        "experiment_harness": (
            os.environ["EXPERIMENT_HARNESS_COMMIT"]
        ),
        "aimapp_runtime": (
            os.environ["AIMAPP_RUNTIME_COMMIT"]
        ),
        "sca_aifnav": (
            os.environ["SCA_COMMIT"]
        ),
    },
}

with (run_dir / "metadata.json").open(
    "w",
    encoding="utf-8",
) as file:
    json.dump(
        metadata,
        file,
        indent=2,
        ensure_ascii=False,
    )

print("WROTE:", run_dir / "metadata.json")
PY

echo "$TOPIC_REGEX" > "$RUN_DIR/topic_regex.txt"

# ----------------------------------------------------------------------
# Preserve exact map and Nav2 configuration.
# ----------------------------------------------------------------------

AIMAPP_PREFIX="$(
    ros2 pkg prefix aimapp 2>/dev/null || true
)"

if [[ -n "$AIMAPP_PREFIX" ]]; then
    PARAM_DIR="$AIMAPP_PREFIX/share/aimapp/params"

    if [[ -f "$PARAM_DIR/warehouse_world.yaml" ]]; then
        cp \
            "$PARAM_DIR/warehouse_world.yaml" \
            "$RUN_DIR/warehouse_world.yaml"
    fi

    if [[ -f "$PARAM_DIR/nav2_humble_params.yaml" ]]; then
        cp \
            "$PARAM_DIR/nav2_humble_params.yaml" \
            "$RUN_DIR/nav2_humble_params.yaml"
    fi
fi

echo "=== CURRENTLY MATCHING TOPICS ==="

CURRENT_TOPICS="$(
    ros2 topic list --include-hidden-topics 2>/dev/null \
    || ros2 topic list
)"

MATCHED_TOPICS="$(
    printf '%s\n' "$CURRENT_TOPICS" \
    | grep -E "$TOPIC_REGEX" \
    || true
)"

if [[ -n "$MATCHED_TOPICS" ]]; then
    printf '%s\n' "$MATCHED_TOPICS"
else
    echo "(none currently visible)"
fi

printf '%s\n' "$MATCHED_TOPICS" \
    > "$RUN_DIR/topics_at_start.txt"

echo
echo "=== METADATA ==="
cat "$RUN_DIR/metadata.json"

if [[ "$MODE" == "--check" ]]; then
    echo
    echo "CHECK PASSED"
    echo "Dynamic topic discovery will remain enabled during real recording."
    echo "No rosbag was started."
    exit 0
fi

echo
echo "============================================================"
echo "ROS BAG RECORDING STARTED"
echo "============================================================"
echo "Start A5 only AFTER this message appears."
echo "Topics matching the regex that appear later will be discovered."
echo "Press Ctrl+C only when the experiment run is finished."
echo "============================================================"

exec ros2 bag record \
    --include-hidden-topics \
    --regex "$TOPIC_REGEX" \
    -o "$RUN_DIR/rosbag"
