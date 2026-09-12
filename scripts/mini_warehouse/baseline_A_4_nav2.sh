#!/usr/bin/env bash

# AIMAPP / SCA-AIFNav Mini Warehouse
# Shared Nav2 backend
#
# IMPORTANT COORDINATE CONVENTION
# --------------------------------
# Gazebo/raw odometry:
#     world coordinates
#
# AIMAPP/SCA cognitive odometry:
#     cognitive = world - physical_start
#
# Therefore the fixed Nav2 occupancy map must be translated by the
# same start offset:
#
#     map_origin_cognitive = map_origin_world - physical_start
#
# This keeps:
#     /agent/odom
#     AIMAPP/SCA cognitive goals
#     Nav2 map coordinates
# in the same coordinate frame.

export PYTHONDONTWRITEBYTECODE=1

set -eo pipefail

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

START_X="${START_X:-0.0}"
START_Y="${START_Y:-0.0}"
START_YAW="${START_YAW:-0.0}"

AIMAPP_SOURCE="$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/src/aimapp"

SOURCE_MAP_YAML="$AIMAPP_SOURCE/aimapp/params/warehouse_world.yaml"

AIMAPP_PREFIX="$(ros2 pkg prefix aimapp)"
RUNTIME_MAP_YAML="$AIMAPP_PREFIX/share/aimapp/params/warehouse_world.yaml"

if [[ ! -f "$SOURCE_MAP_YAML" ]]; then
    echo "ERROR: canonical source map missing:"
    echo "$SOURCE_MAP_YAML"
    exit 1
fi

if [[ ! -f "$RUNTIME_MAP_YAML" ]]; then
    echo "ERROR: installed runtime map missing:"
    echo "$RUNTIME_MAP_YAML"
    exit 1
fi

# Always begin from the canonical source map.
# This also repairs a stale shifted installed map if a previous
# experiment was force-killed before cleanup.
cp -- "$SOURCE_MAP_YAML" "$RUNTIME_MAP_YAML"

restore_map()
{
    # Runtime install is generated data; restore it to the canonical
    # source-map definition whenever this launcher exits normally.
    cp -- "$SOURCE_MAP_YAML" "$RUNTIME_MAP_YAML" 2>/dev/null || true
}

trap restore_map EXIT

echo "=========================================="
echo "Baseline A v2 - Terminal 4"
echo "Nav2 + start-relative map alignment"
echo "=========================================="
echo "START_X=$START_X"
echo "START_Y=$START_Y"
echo "START_YAW=$START_YAW"
echo "Canonical map:"
echo "  $SOURCE_MAP_YAML"
echo "Runtime map:"
echo "  $RUNTIME_MAP_YAML"
echo

START_X="$START_X" \
START_Y="$START_Y" \
SOURCE_MAP_YAML="$SOURCE_MAP_YAML" \
RUNTIME_MAP_YAML="$RUNTIME_MAP_YAML" \
python3 - <<'PY'
import os
import re
from pathlib import Path

sx = float(os.environ["START_X"])
sy = float(os.environ["START_Y"])

source_path = Path(
    os.environ["SOURCE_MAP_YAML"]
)

runtime_path = Path(
    os.environ["RUNTIME_MAP_YAML"]
)

text = source_path.read_text(
    encoding="utf-8"
)

pattern = re.compile(
    r"^origin:\s*\[\s*"
    r"([-+0-9.eE]+)\s*,\s*"
    r"([-+0-9.eE]+)\s*,\s*"
    r"([-+0-9.eE]+)\s*\]\s*$",
    re.MULTILINE,
)

match = pattern.search(text)

if match is None:
    raise RuntimeError(
        "Unable to parse map origin from "
        f"{source_path}"
    )

ox = float(match.group(1))
oy = float(match.group(2))
oyaw = float(match.group(3))

# Cognitive coordinates:
#     C = W - S
#
# Therefore every static-map point must undergo the same transform.
new_ox = ox - sx
new_oy = oy - sy

replacement = (
    "origin: "
    f"[{new_ox:.9f}, "
    f"{new_oy:.9f}, "
    f"{oyaw:.9f}]"
)

shifted = pattern.sub(
    replacement,
    text,
    count=1,
)

runtime_path.write_text(
    shifted,
    encoding="utf-8",
)

print(
    "Original map origin : "
    f"({ox:.3f}, {oy:.3f}, {oyaw:.3f})"
)

print(
    "Physical start      : "
    f"({sx:.3f}, {sy:.3f})"
)

print(
    "Shifted map origin  : "
    f"({new_ox:.3f}, {new_oy:.3f}, {oyaw:.3f})"
)

print(
    "Expected relation   : "
    "map_cognitive = map_world - physical_start"
)

print()

if abs(sx) < 1e-12 and abs(sy) < 1e-12:
    print(
        "INFO: zero start; map origin is unchanged."
    )
else:
    print(
        "INFO: nonzero start; Nav2 map translated "
        "into the cognitive frame."
    )
PY

echo
echo "Runtime map now contains:"
grep '^origin:' "$RUNTIME_MAP_YAML"

echo
echo "Starting Nav2..."

# Keep this shell alive so the EXIT trap can restore the installed
# map after Nav2 stops.
ros2 launch aimapp nav2_humble_launch.py &
NAV2_PID=$!

forward_signal()
{
    local signal="$1"

    if kill -0 "$NAV2_PID" 2>/dev/null; then
        kill "-$signal" "$NAV2_PID" 2>/dev/null || true
    fi
}

trap 'forward_signal INT; exit 130' INT
trap 'forward_signal TERM; exit 143' TERM

wait "$NAV2_PID"
