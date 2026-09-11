#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"
REPRO="$ROOT/aimapp/reproduction"
EXP="$ROOT/experiments/mini_warehouse"
PROBE_DIR="$EXP/smoke/start_pose_probe"
CSV="$EXP/start_poses.csv"

source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"

mkdir -p "$PROBE_DIR"

# Ignore zombie processes: a Z-state gzserver has already exited and
# does not represent a running simulation. Only block on live instances.
LIVE_GZSERVER_PIDS="$(
    {
        ps -C gzserver -o pid=,stat= 2>/dev/null || true
    } | awk '$2 !~ /^Z/ {print $1}'
)"

if [[ -n "$LIVE_GZSERVER_PIDS" ]]; then
    echo "ERROR: live gzserver is already running:"
    ps -o pid,ppid,stat,cmd -p $LIVE_GZSERVER_PIDS
    exit 1
fi

WAREHOUSE_SHARE="$(
    ros2 pkg prefix aws_robomaker_small_warehouse_world
)/share/aws_robomaker_small_warehouse_world"

TB3_SHARE="$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo"

WORLD_DIR="$WAREHOUSE_SHARE/worlds/warehouse_mini"
WORLD_ORIGINAL="$WORLD_DIR/warehouse_mini.world"

# IMPORTANT:
# Keep the temporary world beside the original world.
# Moving a Gazebo world to another directory can break relative
# asset/model paths contained inside the SDF.
WORLD_PROBE="$WORLD_DIR/.warehouse_mini_probe_$$.world"

MODEL="$REPRO/assets/gazebo_models/turtlebot3_waffle_pi_plus/model.sdf"

export GAZEBO_MODEL_PATH="$TB3_SHARE/models:$WAREHOUSE_SHARE/models:$WAREHOUSE_SHARE/worlds:${GAZEBO_MODEL_PATH:-}"
export GAZEBO_PLUGIN_PATH="/opt/ros/humble/lib:${GAZEBO_PLUGIN_PATH:-}"

echo "Creating temporary probe world..."

python3 - "$WORLD_ORIGINAL" "$WORLD_PROBE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])

text = source.read_text(
    encoding="utf-8",
    errors="replace",
)

plugin = """
    <!-- Temporary plugin used only for start-pose probing. -->
    <plugin name="gazebo_ros_state" filename="libgazebo_ros_state.so">
      <ros>
        <namespace>/gazebo</namespace>
      </ros>
      <update_rate>20.0</update_rate>
    </plugin>
"""

if "libgazebo_ros_state.so" not in text:
    marker = "</world>"

    index = text.rfind(marker)

    if index < 0:
        raise RuntimeError(
            "Could not locate </world> in source world."
        )

    text = (
        text[:index]
        + plugin
        + text[index:]
    )

target.write_text(
    text,
    encoding="utf-8",
)

print("SOURCE :", source)
print("PROBE  :", target)
PY


SERVER_PID=""

cleanup()
{
    echo
    echo "Cleaning temporary Gazebo probe..."

    if [[ -n "$SERVER_PID" ]]; then
        kill -INT -- "-$SERVER_PID" 2>/dev/null || true
        sleep 2
        kill -TERM -- "-$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    rm -f "$WORLD_PROBE"
}

trap cleanup EXIT INT TERM


echo
echo "Starting Mini Warehouse probe gzserver..."

# Match the official/formal A1 startup working directory exactly.
# warehouse_mini.world contains file://models/... references, which
# depend on Gazebo being launched from WAREHOUSE_SHARE.
(
    cd "$WAREHOUSE_SHARE"

    exec setsid gzserver --verbose \
        -s libgazebo_ros_init.so \
        -s libgazebo_ros_factory.so \
        "$WORLD_PROBE"
) > "$PROBE_DIR/gzserver.log" 2>&1 &

SERVER_PID=$!


echo "Waiting for Gazebo services..."

READY=0

for i in $(seq 1 90)
do
    SPAWN_OK=0
    SET_OK=0
    GET_OK=0

    ros2 service list 2>/dev/null \
      | grep -qx "/spawn_entity" \
      && SPAWN_OK=1 || true

    ros2 service list 2>/dev/null \
      | grep -qx "/gazebo/set_entity_state" \
      && SET_OK=1 || true

    ros2 service list 2>/dev/null \
      | grep -qx "/gazebo/get_entity_state" \
      && GET_OK=1 || true

    if [[ \
        "$SPAWN_OK" -eq 1 \
        && "$SET_OK" -eq 1 \
        && "$GET_OK" -eq 1 \
    ]]; then
        READY=1
        break
    fi

    sleep 1
done


if [[ "$READY" -ne 1 ]]; then
    echo
    echo "ERROR: required Gazebo services did not appear."
    echo
    echo "Available Gazebo/entity services:"
    ros2 service list 2>/dev/null \
      | grep -E "entity|spawn|gazebo" \
      || true

    echo
    echo "Last 80 gzserver log lines:"
    tail -80 "$PROBE_DIR/gzserver.log" || true

    exit 1
fi


echo
echo "Services ready:"
ros2 service list \
  | grep -E \
    "^/spawn_entity$|^/gazebo/(get|set)_entity_state$"


echo
echo "Spawning probe robot..."

ros2 run gazebo_ros spawn_entity.py \
    -entity waffle_pi_plus \
    -file "$MODEL" \
    -x 0.0 \
    -y 0.0 \
    -z 0.01 \
    > "$PROBE_DIR/spawn.log" \
    2>&1


echo "Waiting for /scan..."

SCAN_READY=0

for i in $(seq 1 60)
do
    if ros2 topic type /scan \
        2>/dev/null \
        | grep -q "sensor_msgs/msg/LaserScan"
    then
        SCAN_READY=1
        break
    fi

    sleep 1
done

if [[ "$SCAN_READY" -ne 1 ]]; then
    echo "ERROR: /scan did not appear."
    tail -80 "$PROBE_DIR/gzserver.log" || true
    exit 1
fi


echo
echo "============================================================"
echo "PROBING REAL GAZEBO FREE SPACE"
echo "============================================================"

python3 \
    "$REPRO/scripts/mini_warehouse/probe_start_poses.py" \
    --output "$CSV" \
    --count 10 \
    --min-coordinate -2.5 \
    --max-coordinate 2.5 \
    --step 0.5 \
    --minimum-clearance 0.35


echo
echo "============================================================"
echo "START POSE PROBE COMPLETE"
echo "============================================================"

cat "$CSV"
