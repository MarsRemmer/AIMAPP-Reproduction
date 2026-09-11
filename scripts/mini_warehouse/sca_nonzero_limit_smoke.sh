#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"
REPRO="$ROOT/experiments"
SCA_SRC="$ROOT/sca_aifnav/runtime_ws/src/sca_aifnav"
EXP="$ROOT/results/mini_warehouse"
SMOKE="$EXP/smoke/sca_nonzero_candidate_2"

START_X="-2.5"
START_Y="-2.5"
START_YAW="0.0"

ACTION_LIMIT="3"

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
source "$ROOT/sca_aifnav/runtime_ws/install/setup.bash"
set -u

cd "$REPRO"

rm -rf "$SMOKE"
mkdir -p "$SMOKE/logs"

echo "============================================================"
echo "SCA NONZERO-START + ACTION-LIMIT SMOKE"
echo "============================================================"
echo "physical start = ($START_X, $START_Y)"
echo "action limit   = $ACTION_LIMIT"

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
echo "1. CLEAN OLD STACK"
echo "============================================================"

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
    tail -100 "$SMOKE/logs/A1_server.log"
    exit 1
fi

echo "A1 ready."


echo
echo "============================================================"
echo "3. START A3 - ROBOT AT CANDIDATE 2"
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
    echo "ERROR: robot topics unavailable."
    tail -100 "$SMOKE/logs/A3_robot.log"
    exit 1
fi

echo "A3 ready."


echo
echo "============================================================"
echo "4. START A4 - NAV2"
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
echo "5. START SCA A5"
echo "============================================================"

SCA_RUN_DIR="$SMOKE/sca_native" \
EXPERIMENT_ACTION_LIMIT="$ACTION_LIMIT" \
setsid bash \
    "$SCA_SRC/scripts/mini_warehouse/baseline_A_5_sca.sh" \
    > "$SMOKE/logs/A5_sca.log" \
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
        echo "ERROR: SCA exited during startup."
        tail -150 "$SMOKE/logs/A5_sca.log"
        exit 1
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: /agent/odom unavailable."
    tail -150 "$SMOKE/logs/A5_sca.log"
    exit 1
fi


echo
echo "============================================================"
echo "6. VERIFY NONZERO -> COGNITIVE ORIGIN ALIGNMENT"
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
        super().__init__("sca_start_alignment_monitor")

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

raw_error = math.hypot(
    rx - sx,
    ry - sy,
)

agent_error = math.hypot(
    ax,
    ay,
)

print()
print("SCA FRAME ALIGNMENT")
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
    f"raw-vs-start error      : "
    f"{raw_error:.3f} m"
)
print(
    f"agent-origin error      : "
    f"{agent_error:.3f} m"
)

node.destroy_node()
rclpy.shutdown()

if raw_error > 0.30:
    raise RuntimeError(
        "FAIL: raw odometry is not at requested "
        "physical start"
    )

if agent_error > 0.30:
    raise RuntimeError(
        "FAIL: SCA /agent/odom did not establish "
        "the cognitive origin"
    )

print()
print(
    "PASS: SCA nonzero physical start -> "
    "cognitive origin alignment"
)
PY


echo
echo "============================================================"
echo "7. WAIT FOR 3-ACTION EXPERIMENT COMPLETION"
echo "============================================================"

COMPLETE=0

# Up to 20 minutes for three full observe-plan-act cycles.
for i in $(seq 1 240)
do
    if grep -q \
        "EXPERIMENT_COMPLETE actions=$ACTION_LIMIT limit=$ACTION_LIMIT" \
        "$SMOKE/logs/A5_sca.log"
    then
        COMPLETE=1
        break
    fi

    if ! kill -0 "$A5_PID" 2>/dev/null; then
        echo "ERROR: SCA exited before experiment completion."
        tail -180 "$SMOKE/logs/A5_sca.log"
        exit 1
    fi

    if (( i % 12 == 0 )); then
        echo "Still running: $((i * 5)) s"

        grep -E \
            'Sending Nav2 goal|Nav2 goal accepted|Nav2 goal succeeded|EXPERIMENT_COMPLETE' \
            "$SMOKE/logs/A5_sca.log" \
            | tail -10 \
            || true
    fi

    sleep 5
done

if [[ "$COMPLETE" -ne 1 ]]; then
    echo "ERROR: experiment limit not reached within timeout."
    tail -220 "$SMOKE/logs/A5_sca.log"
    exit 1
fi


echo
echo "============================================================"
echo "8. VERIFY NAV2 WAS ACTUALLY USED"
echo "============================================================"

if grep -q \
    'Sending Nav2 goal' \
    "$SMOKE/logs/A5_sca.log"
then
    echo "PASS: at least one translational Nav2 goal was sent."
else
    echo "WARNING:"
    echo "All first $ACTION_LIMIT actions may have been STAY."
    echo "The action-limit test passed, but no Nav2 goal appeared."
fi


echo
echo "============================================================"
echo "9. RUNTIME EVIDENCE"
echo "============================================================"

grep -E \
    'Sending Nav2 goal|Nav2 goal accepted|Nav2 goal succeeded|Nav2 goal ended|EXPERIMENT_COMPLETE' \
    "$SMOKE/logs/A5_sca.log" \
    | tail -60 \
    || true


echo
echo "============================================================"
echo "10. RESULT"
echo "============================================================"

if ! grep -q \
    "EXPERIMENT_COMPLETE actions=$ACTION_LIMIT limit=$ACTION_LIMIT" \
    "$SMOKE/logs/A5_sca.log"
then
    echo "FAIL: experiment completion marker missing."
    exit 1
fi

echo "PASS: SCA nonzero-start alignment"
echo "PASS: SCA runtime action limit = $ACTION_LIMIT"
echo "Logs: $SMOKE/logs"


echo
echo "============================================================"
echo "11. REPOSITORY STATUS"
echo "============================================================"

echo "--- AIMAPP reproduction ---"
git -C "$REPRO" status --short

echo
echo "--- SCA-AIFNav ---"
git -C "$SCA_SRC" status --short

