#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"
REPRO="$ROOT/aimapp/reproduction"
EXP="$ROOT/experiments/mini_warehouse"
SMOKE="$EXP/smoke/nonzero_start_candidate_2"

START_X="-2.5"
START_Y="-2.5"
START_YAW="0.0"

export PYTHONDONTWRITEBYTECODE=1

# ROS setup scripts are not safe under `set -u`.
set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
set -u

cd "$REPRO"

mkdir -p "$SMOKE/logs"
rm -rf "$SMOKE/aimapp_native"
mkdir -p "$SMOKE/aimapp_native/tests"

echo "============================================================"
echo "0. VERIFY PARAMETERIZED A3 / A5"
echo "============================================================"

grep -n -E 'START_X|START_Y|START_YAW|spawn_entity' \
    scripts/mini_warehouse/baseline_A_3_spawn_robot.sh \
    || true

echo
grep -n -E 'START_X|START_Y|START_YAW|agent_launch.py' \
    scripts/mini_warehouse/baseline_A_5_agent.sh \
    || true


echo
echo "============================================================"
echo "1. CLEAN OLD STACK"
echo "============================================================"

pkill -INT -x gzclient 2>/dev/null || true

LIVE="$(
    {
        ps -C gzserver -o pid=,stat= 2>/dev/null || true
    } | awk '$2 !~ /^Z/ {print $1}'
)"

if [[ -n "$LIVE" ]]; then
    kill -INT $LIVE 2>/dev/null || true
    sleep 2
    kill -TERM $LIVE 2>/dev/null || true
    sleep 2
fi

ros2 daemon stop >/dev/null 2>&1 || true
sleep 1
ros2 daemon start >/dev/null
sleep 1


A1_PID=""
A3_PID=""
A4_PID=""
A5_PID=""

cleanup()
{
    set +e

    echo
    echo "============================================================"
    echo "CLEANUP"
    echo "============================================================"

    for pid in \
        "$A5_PID" \
        "$A4_PID" \
        "$A3_PID" \
        "$A1_PID"
    do
        if [[ -n "$pid" ]]; then
            kill -INT -- "-$pid" 2>/dev/null || true
        fi
    done

    sleep 3

    for pid in \
        "$A5_PID" \
        "$A4_PID" \
        "$A3_PID" \
        "$A1_PID"
    do
        if [[ -n "$pid" ]]; then
            kill -TERM -- "-$pid" 2>/dev/null || true
        fi
    done

    sleep 2

    LIVE="$(
        {
            ps -C gzserver -o pid=,stat= 2>/dev/null || true
        } | awk '$2 !~ /^Z/ {print $1}'
    )"

    if [[ -n "$LIVE" ]]; then
        kill -KILL $LIVE 2>/dev/null || true
    fi

    ros2 daemon stop >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM


echo
echo "============================================================"
echo "2. START A1 - GAZEBO"
echo "============================================================"

setsid bash \
    scripts/mini_warehouse/baseline_A_1_server.sh \
    > "$SMOKE/logs/A1_server.log" \
    2>&1 &

A1_PID=$!

READY=0

for _ in $(seq 1 90)
do
    if ros2 service list 2>/dev/null \
        | grep -qx '/spawn_entity'
    then
        READY=1
        break
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: Gazebo factory unavailable."
    tail -80 "$SMOKE/logs/A1_server.log"
    exit 1
fi

echo "A1 ready."


echo
echo "============================================================"
echo "3. START A3 - SPAWN AT (-2.5,-2.5)"
echo "============================================================"

START_X="$START_X" \
START_Y="$START_Y" \
START_YAW="$START_YAW" \
setsid bash \
    scripts/mini_warehouse/baseline_A_3_spawn_robot.sh \
    > "$SMOKE/logs/A3_robot.log" \
    2>&1 &

A3_PID=$!

READY=0

for _ in $(seq 1 60)
do
    ODOM=0
    SCAN=0

    ros2 topic list 2>/dev/null \
        | grep -qx '/odom' \
        && ODOM=1 || true

    ros2 topic list 2>/dev/null \
        | grep -qx '/scan' \
        && SCAN=1 || true

    if [[ "$ODOM" -eq 1 && "$SCAN" -eq 1 ]]; then
        READY=1
        break
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: /odom or /scan unavailable."
    tail -100 "$SMOKE/logs/A3_robot.log"
    exit 1
fi

echo "A3 ready."


echo
echo "============================================================"
echo "4. RAW ODOM BEFORE AIMAPP ALIGNMENT"
echo "============================================================"

timeout 10 ros2 topic echo /odom --once \
    | grep -A8 'position:' \
    | head -10 \
    || true


echo
echo "============================================================"
echo "5. START A4 - NAV2"
echo "============================================================"

setsid bash \
    scripts/mini_warehouse/baseline_A_4_nav2.sh \
    > "$SMOKE/logs/A4_nav2.log" \
    2>&1 &

A4_PID=$!

READY=0

for _ in $(seq 1 120)
do
    if ros2 action list 2>/dev/null \
        | grep -qx '/navigate_to_pose'
    then
        READY=1
        break
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: NavigateToPose unavailable."
    tail -120 "$SMOKE/logs/A4_nav2.log"
    exit 1
fi

echo "A4 ready."


echo
echo "============================================================"
echo "6. START A5 - AIMAPP"
echo "============================================================"

START_X="$START_X" \
START_Y="$START_Y" \
START_YAW="$START_YAW" \
AIMAPP_RUN_CWD="$SMOKE/aimapp_native" \
setsid bash \
    scripts/mini_warehouse/baseline_A_5_agent.sh \
    > "$SMOKE/logs/A5_agent.log" \
    2>&1 &

A5_PID=$!

READY=0

for _ in $(seq 1 60)
do
    if ros2 topic list 2>/dev/null \
        | grep -qx '/agent/odom'
    then
        READY=1
        break
    fi

    if ! kill -0 "$A5_PID" 2>/dev/null; then
        echo "ERROR: AIMAPP exited during startup."
        tail -120 "$SMOKE/logs/A5_agent.log"
        exit 1
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: /agent/odom unavailable."
    tail -120 "$SMOKE/logs/A5_agent.log"
    exit 1
fi


echo
echo "============================================================"
echo "7. FRAME ALIGNMENT CHECK"
echo "============================================================"

START_X="$START_X" \
START_Y="$START_Y" \
python3 - <<'PY'
import math
import os
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node


sx = float(os.environ["START_X"])
sy = float(os.environ["START_Y"])


class Monitor(Node):
    def __init__(self):
        super().__init__("frame_alignment_monitor")

        self.raw = None
        self.agent = None

        self.create_subscription(
            Odometry,
            "/odom",
            self.raw_cb,
            10,
        )

        self.create_subscription(
            Odometry,
            "/agent/odom",
            self.agent_cb,
            10,
        )

    def raw_cb(self, msg):
        self.raw = msg

    def agent_cb(self, msg):
        self.agent = msg


rclpy.init()
node = Monitor()

deadline = time.monotonic() + 20.0

while (
    time.monotonic() < deadline
    and (
        node.raw is None
        or node.agent is None
    )
):
    rclpy.spin_once(
        node,
        timeout_sec=0.1,
    )

if node.raw is None:
    raise RuntimeError("No /odom received")

if node.agent is None:
    raise RuntimeError("No /agent/odom received")

rx = float(node.raw.pose.pose.position.x)
ry = float(node.raw.pose.pose.position.y)

ax = float(node.agent.pose.pose.position.x)
ay = float(node.agent.pose.pose.position.y)

raw_world_error = math.hypot(
    rx - sx,
    ry - sy,
)

agent_origin_error = math.hypot(
    ax,
    ay,
)

shift_x = ax - rx
shift_y = ay - ry

print()
print("FRAME ALIGNMENT RESULT")
print("----------------------------------------")
print(
    f"requested physical start : "
    f"({sx:.3f}, {sy:.3f})"
)
print(
    f"raw /odom               : "
    f"({rx:.3f}, {ry:.3f})"
)
print(
    f"/agent/odom             : "
    f"({ax:.3f}, {ay:.3f})"
)
print(
    f"observed odom shift     : "
    f"({shift_x:.3f}, {shift_y:.3f})"
)
print(
    f"expected shift          : "
    f"({-sx:.3f}, {-sy:.3f})"
)
print(
    f"raw-vs-start error      : "
    f"{raw_world_error:.3f} m"
)
print(
    f"agent-origin error      : "
    f"{agent_origin_error:.3f} m"
)

node.destroy_node()
rclpy.shutdown()

if raw_world_error > 0.30:
    raise RuntimeError(
        "FAIL: raw /odom is not expressed at the "
        "requested physical world start."
    )

if agent_origin_error > 0.30:
    raise RuntimeError(
        "FAIL: /agent/odom does not map the "
        "nonzero start to cognitive origin."
    )

print()
print(
    "PASS: physical nonzero start -> "
    "AIMAPP cognitive origin alignment"
)
PY


echo
echo "============================================================"
echo "8. WAIT FOR FIRST AIMAPP NAV2 GOAL"
echo "============================================================"

FOUND=0

for i in $(seq 1 96)
do
    if grep -q \
        'Sending nav2 goal as x:' \
        "$SMOKE/logs/A5_agent.log"
    then
        FOUND=1
        break
    fi

    if ! kill -0 "$A5_PID" 2>/dev/null; then
        echo "ERROR: AIMAPP exited before first Nav2 goal."
        tail -150 "$SMOKE/logs/A5_agent.log"
        exit 1
    fi

    if (( i % 6 == 0 )); then
        echo "Waiting for first Nav2 goal: $((i * 5)) s"
    fi

    sleep 5
done

if [[ "$FOUND" -ne 1 ]]; then
    echo "ERROR: no AIMAPP Nav2 goal within 8 minutes."
    tail -180 "$SMOKE/logs/A5_agent.log"
    exit 1
fi

echo "First AIMAPP Nav2 goal detected."

sleep 10


echo
echo "============================================================"
echo "9. AIMAPP / NAV2 EVIDENCE"
echo "============================================================"

grep -E \
    'Initial pose set|Sending nav2 goal|Goal nav2 accepted|reached with nav2|Goal not reached with nav2|step:|pose reached' \
    "$SMOKE/logs/A5_agent.log" \
    | tail -50 \
    || true


echo
echo "============================================================"
echo "10. AMCL POSE"
echo "============================================================"

timeout 10 ros2 topic echo /amcl_pose --once \
    | grep -A8 'position:' \
    | head -10 \
    || echo "No /amcl_pose sample captured."


echo
echo "============================================================"
echo "11. RESULT"
echo "============================================================"

echo "Physical start = ($START_X, $START_Y)"
echo "Smoke logs     = $SMOKE/logs"

echo
echo "PASS: nonzero-start smoke reached first Nav2 goal stage."

echo
echo "============================================================"
echo "12. GIT STATUS"
echo "============================================================"

git status --short
