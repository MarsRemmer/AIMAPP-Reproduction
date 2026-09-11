#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"
REPRO="$ROOT/experiments"
AIMAPP_RUNTIME="$ROOT/aimapp/runtime_ws/src/aimapp"
SCA="$ROOT/sca_aifnav/runtime_ws/src/sca_aifnav"
EXP="$ROOT/results/mini_warehouse"

POSES="$REPRO/configs/mini_warehouse/start_poses.csv"

TARGET_PAIRS="${TARGET_PAIRS:-5}"

# 200-action smoke timing suggests ~1–2 h/run is plausible.
# Four hours is a conservative safety ceiling, not an experiment metric.
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-14400}"

MODE="${1:---check}"

if [[ "$MODE" != "--check" && "$MODE" != "--run" ]]; then
    echo "Usage:"
    echo "  $0 --check"
    echo "  $0 --run"
    exit 2
fi

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$ROOT/aimapp/runtime_ws/install/setup.bash"
source "$ROOT/sca_aifnav/runtime_ws/install/setup.bash"
set -u

cd "$REPRO"

A1="$REPRO/scripts/mini_warehouse/baseline_A_1_server.sh"
A3="$REPRO/scripts/mini_warehouse/baseline_A_3_spawn_robot.sh"
A4="$REPRO/scripts/mini_warehouse/baseline_A_4_nav2.sh"
A5_AIM="$REPRO/scripts/mini_warehouse/baseline_A_5_agent.sh"
REC="$REPRO/scripts/mini_warehouse/common_run_recorder.sh"
A5_SCA="$SCA/scripts/mini_warehouse/baseline_A_5_sca.sh"

BATCH_ID="${BATCH_ID:-$(date +%Y%m%d_%H%M%S)}"
BATCH_DIR="$EXP/formal/_batches/$BATCH_ID"

A1_PID=""
A3_PID=""
A4_PID=""
A5_PID=""
REC_PID=""

CURRENT_METHOD=""
CURRENT_RUN=""
CURRENT_RUN_DIR=""


repo_fingerprint()
{
    local repo="$1"

    {
        git -C "$repo" rev-parse HEAD
        git -C "$repo" status --porcelain=v1
        git -C "$repo" diff --no-ext-diff HEAD
    } | sha256sum | awk '{print $1}'
}


snapshot_repo()
{
    local repo="$1"
    local label="$2"
    local output="$3/provenance/$label"

    mkdir -p "$output"

    git -C "$repo" rev-parse HEAD \
        > "$output/head.txt"

    git -C "$repo" branch --show-current \
        > "$output/branch.txt"

    git -C "$repo" status --short \
        > "$output/status.txt"

    git -C "$repo" diff --no-ext-diff HEAD \
        > "$output/working_tree.diff"
}


stop_group()
{
    local pid="${1:-}"
    local grace="${2:-10}"

    if [[ -z "$pid" ]]; then
        return
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        return
    fi

    kill -INT -- "-$pid" 2>/dev/null || true

    for _ in $(seq 1 "$grace")
    do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            return
        fi

        sleep 1
    done

    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || true
    fi

    wait "$pid" 2>/dev/null || true
}


cleanup_current_run()
{
    set +e

    # Stop rosbag first so its database is closed cleanly.
    stop_group "$REC_PID" 20
    REC_PID=""

    stop_group "$A5_PID" 8
    A5_PID=""

    stop_group "$A4_PID" 8
    A4_PID=""

    stop_group "$A3_PID" 5
    A3_PID=""

    stop_group "$A1_PID" 8
    A1_PID=""

    ros2 daemon stop >/dev/null 2>&1 || true
    sleep 1

    set -e
}


abort_batch()
{
    echo
    echo "============================================================"
    echo "BATCH INTERRUPTED"
    echo "============================================================"

    cleanup_current_run
    exit 130
}

trap abort_batch INT TERM


preflight()
{
    echo "============================================================"
    echo "MINI WAREHOUSE FORMAL BATCH PREFLIGHT"
    echo "============================================================"
    echo "Batch ID           : $BATCH_ID"
    echo "Target paired runs : $TARGET_PAIRS"
    echo "Run timeout        : $RUN_TIMEOUT_SEC s"
    echo

    for f in \
        "$A1" \
        "$A3" \
        "$A4" \
        "$A5_AIM" \
        "$REC" \
        "$A5_SCA"
    do
        if [[ ! -f "$f" ]]; then
            echo "ERROR: missing $f"
            exit 1
        fi

        bash -n "$f"
    done

    if [[ ! -f "$POSES" ]]; then
        echo "ERROR: missing $POSES"
        exit 1
    fi

    POSE_COUNT="$(
        tail -n +2 "$POSES" \
        | sed '/^[[:space:]]*$/d' \
        | wc -l
    )"

    echo "Candidate poses     : $POSE_COUNT"

    if (( POSE_COUNT < 10 )); then
        echo "ERROR: expected 10 prepared candidate poses."
        exit 1
    fi

    if ! grep -q 'START_X' "$A3"; then
        echo "ERROR: A3 is not start-pose parameterized."
        exit 1
    fi

    if ! grep -q 'x:="\$START_X"' "$A5_AIM"; then
        echo "ERROR: AIMAPP A5 is not start-pose parameterized."
        exit 1
    fi

    if ! grep -q 'experiment_action_limit' "$A5_SCA"; then
        echo "ERROR: SCA A5 does not expose action limit."
        exit 1
    fi

    if ! grep -q 'os.environ\["START_X"\]' "$REC"; then
        echo "ERROR: recorder does not preserve physical start pose."
        exit 1
    fi

    LIVE_GZ="$(
        {
            ps -C gzserver -o pid=,stat= 2>/dev/null || true
        } | awk '$2 !~ /^Z/ {print $1}'
    )"

    if [[ -n "$LIVE_GZ" ]]; then
        echo "ERROR: a live gzserver already exists:"
        ps -o pid,ppid,stat,cmd -p $LIVE_GZ
        exit 1
    fi

    FREE_GB="$(
        df -BG "$EXP" \
        | awk 'NR==2 {gsub("G","",$4); print $4}'
    )"

    echo "Free disk          : ${FREE_GB} GB"

    if (( FREE_GB < 15 )); then
        echo "ERROR: less than 15 GB free."
        echo "Formal AIMAPP native outputs can be large."
        exit 1
    elif (( FREE_GB < 50 )); then
        echo "WARNING: less than 50 GB free."
        echo "Do not delete experiment data during a run."
    fi

    echo
    echo "Start poses:"
    cat "$POSES"

    echo
    echo "Source fingerprints:"
    echo "  reproduction : $(repo_fingerprint "$REPRO")"
    echo "  AIMAPP       : $(repo_fingerprint "$AIMAPP_RUNTIME")"
    echo "  SCA          : $(repo_fingerprint "$SCA")"

    echo
    echo "PREFLIGHT PASSED"
}


wait_for_spawn()
{
    for _ in $(seq 1 90)
    do
        if ros2 service list 2>/dev/null \
            | grep -qx '/spawn_entity'
        then
            return 0
        fi

        sleep 1
    done

    return 1
}


wait_for_robot()
{
    for _ in $(seq 1 60)
    do
        local odom=0
        local scan=0

        ros2 topic list 2>/dev/null \
            | grep -qx '/odom' \
            && odom=1 || true

        ros2 topic list 2>/dev/null \
            | grep -qx '/scan' \
            && scan=1 || true

        if [[ "$odom" -eq 1 && "$scan" -eq 1 ]]; then
            return 0
        fi

        sleep 1
    done

    return 1
}


wait_for_nav2()
{
    for _ in $(seq 1 120)
    do
        if ros2 action list 2>/dev/null \
            | grep -qx '/navigate_to_pose'
        then
            return 0
        fi

        sleep 1
    done

    return 1
}


write_status()
{
    local status="$1"
    local reason="$2"
    local elapsed="$3"

    STATUS="$status" \
    REASON="$reason" \
    ELAPSED="$elapsed" \
    METHOD="$CURRENT_METHOD" \
    RUN_NAME="$CURRENT_RUN" \
    python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

path = Path(os.environ["CURRENT_RUN_DIR"]) if "CURRENT_RUN_DIR" in os.environ else None
PY

    cat > "$CURRENT_RUN_DIR/run_status.txt" <<TXT
status=$status
reason=$reason
method=$CURRENT_METHOD
run_name=$CURRENT_RUN
elapsed_sec=$elapsed
finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TXT
}


run_one()
{
    local method="$1"
    local candidate="$2"
    local sx="$3"
    local sy="$4"
    local yaw="$5"

    CURRENT_METHOD="$method"
    CURRENT_RUN="${BATCH_ID}_candidate_$(printf '%02d' "$candidate")"
    CURRENT_RUN_DIR="$EXP/formal/$method/$CURRENT_RUN"

    export START_X="$sx"
    export START_Y="$sy"
    export START_YAW="$yaw"

    mkdir -p \
        "$CURRENT_RUN_DIR/logs" \
        "$CURRENT_RUN_DIR/provenance"

    echo
    echo "============================================================"
    echo "START RUN"
    echo "============================================================"
    echo "Method    : $method"
    echo "Candidate : $candidate"
    echo "Start     : ($sx, $sy, yaw=$yaw)"
    echo "Run       : $CURRENT_RUN"
    echo "Output    : $CURRENT_RUN_DIR"

    # Freeze exact start protocol with every run.
    cp "$POSES" "$CURRENT_RUN_DIR/start_poses.csv"

    snapshot_repo \
        "$REPRO" \
        "aimapp_reproduction" \
        "$CURRENT_RUN_DIR"

    snapshot_repo \
        "$AIMAPP_RUNTIME" \
        "aimapp_runtime" \
        "$CURRENT_RUN_DIR"

    snapshot_repo \
        "$SCA" \
        "sca_aifnav" \
        "$CURRENT_RUN_DIR"

    # Ensure source state did not change after batch start.
    if [[ "$(repo_fingerprint "$REPRO")" != "$FP_REPRO" ]]; then
        echo "ERROR: reproduction source changed during batch."
        return 1
    fi

    if [[ "$(repo_fingerprint "$AIMAPP_RUNTIME")" != "$FP_AIMAPP" ]]; then
        echo "ERROR: AIMAPP runtime source changed during batch."
        return 1
    fi

    if [[ "$(repo_fingerprint "$SCA")" != "$FP_SCA" ]]; then
        echo "ERROR: SCA source changed during batch."
        return 1
    fi

    LIVE_GZ="$(
        {
            ps -C gzserver -o pid=,stat= 2>/dev/null || true
        } | awk '$2 !~ /^Z/ {print $1}'
    )"

    if [[ -n "$LIVE_GZ" ]]; then
        echo "ERROR: unexpected live gzserver before run."
        return 1
    fi

    ros2 daemon stop >/dev/null 2>&1 || true
    sleep 1
    ros2 daemon start >/dev/null
    sleep 1

    # --------------------------------------------------------
    # A1
    # --------------------------------------------------------
    setsid bash "$A1" \
        > "$CURRENT_RUN_DIR/logs/A1_server.log" \
        2>&1 &

    A1_PID=$!

    if ! wait_for_spawn; then
        echo "ERROR: Gazebo startup failed."
        tail -100 "$CURRENT_RUN_DIR/logs/A1_server.log" || true
        cleanup_current_run
        return 1
    fi

    # --------------------------------------------------------
    # A3
    # --------------------------------------------------------
    START_X="$sx" \
    START_Y="$sy" \
    START_YAW="$yaw" \
    setsid bash "$A3" \
        > "$CURRENT_RUN_DIR/logs/A3_robot.log" \
        2>&1 &

    A3_PID=$!

    if ! wait_for_robot; then
        echo "ERROR: robot topics failed."
        tail -100 "$CURRENT_RUN_DIR/logs/A3_robot.log" || true
        cleanup_current_run
        return 1
    fi

    # --------------------------------------------------------
    # A4
    # --------------------------------------------------------
    setsid bash "$A4" \
        > "$CURRENT_RUN_DIR/logs/A4_nav2.log" \
        2>&1 &

    A4_PID=$!

    if ! wait_for_nav2; then
        echo "ERROR: Nav2 startup failed."
        tail -120 "$CURRENT_RUN_DIR/logs/A4_nav2.log" || true
        cleanup_current_run
        return 1
    fi

    # --------------------------------------------------------
    # Common rosbag recorder
    # --------------------------------------------------------
    START_X="$sx" \
    START_Y="$sy" \
    START_YAW="$yaw" \
    setsid bash "$REC" "$method" "$CURRENT_RUN" \
        > "$CURRENT_RUN_DIR/logs/recorder.log" \
        2>&1 &

    REC_PID=$!

    sleep 5

    if ! kill -0 "$REC_PID" 2>/dev/null; then
        echo "ERROR: recorder failed to start."
        cat "$CURRENT_RUN_DIR/logs/recorder.log" || true
        cleanup_current_run
        return 1
    fi

    # --------------------------------------------------------
    # A5
    # --------------------------------------------------------
    if [[ "$method" == "aimapp_nav2" ]]; then

        mkdir -p "$CURRENT_RUN_DIR/aimapp_native/tests"

        START_X="$sx" \
        START_Y="$sy" \
        START_YAW="$yaw" \
        AIMAPP_RUN_CWD="$CURRENT_RUN_DIR/aimapp_native" \
        setsid bash "$A5_AIM" \
            > "$CURRENT_RUN_DIR/logs/A5_agent.log" \
            2>&1 &

    elif [[ "$method" == "sca_baseline_nav2" ]]; then

        SCA_RUN_DIR="$CURRENT_RUN_DIR/sca_native" \
        EXPERIMENT_ACTION_LIMIT=200 \
        setsid bash "$A5_SCA" \
            > "$CURRENT_RUN_DIR/logs/A5_agent.log" \
            2>&1 &

    else
        echo "ERROR: unknown method $method"
        cleanup_current_run
        return 1
    fi

    A5_PID=$!

    local started
    local now
    local elapsed
    local next_report
    local success=0
    local reason="unknown"

    started="$(date +%s)"
    next_report=60

    while true
    do
        now="$(date +%s)"
        elapsed=$((now - started))

        if [[ "$method" == "aimapp_nav2" ]]; then

            # Official AIMAPP logs this exactly once after each
            # completed policy iteration.
            completed="$(
                grep -c \
                    'HighLevelNav_model.*Next action' \
                    "$CURRENT_RUN_DIR/logs/A5_agent.log" \
                    2>/dev/null \
                || true
            )"

            if (( completed >= 200 )); then
                success=1
                reason="completed_200_actions"
                break
            fi

            if grep -Eq \
                'main\.py-1.*process has died|process has died.*main\.py' \
                "$CURRENT_RUN_DIR/logs/A5_agent.log" \
                2>/dev/null
            then
                success=0
                reason="aimapp_main_process_died"
                break
            fi

        else

            if grep -q \
                'EXPERIMENT_COMPLETE actions=200 limit=200' \
                "$CURRENT_RUN_DIR/logs/A5_agent.log" \
                2>/dev/null
            then
                success=1
                reason="completed_200_actions"
                break
            fi

            if ! kill -0 "$A5_PID" 2>/dev/null; then
                success=0
                reason="sca_process_exited_early"
                break
            fi
        fi

        if (( elapsed >= RUN_TIMEOUT_SEC )); then
            success=0
            reason="run_timeout"
            break
        fi

        if (( elapsed >= next_report )); then
            if [[ "$method" == "aimapp_nav2" ]]; then
                echo \
                    "[$method candidate $candidate] " \
                    "elapsed=${elapsed}s completed=${completed}/200"
            else
                goals="$(
                    grep -c \
                        'Nav2 goal succeeded' \
                        "$CURRENT_RUN_DIR/logs/A5_agent.log" \
                        2>/dev/null \
                    || true
                )"

                echo \
                    "[$method candidate $candidate] " \
                    "elapsed=${elapsed}s nav2_successes=$goals"
            fi

            next_report=$((next_report + 60))
        fi

        sleep 10
    done

    # Preserve final messages before closing the recorder.
    sleep 3

    stop_group "$REC_PID" 20
    REC_PID=""

    stop_group "$A5_PID" 8
    A5_PID=""

    stop_group "$A4_PID" 8
    A4_PID=""

    stop_group "$A3_PID" 5
    A3_PID=""

    stop_group "$A1_PID" 8
    A1_PID=""

    ros2 daemon stop >/dev/null 2>&1 || true
    sleep 2

    now="$(date +%s)"
    elapsed=$((now - started))

    cat > "$CURRENT_RUN_DIR/run_status.txt" <<TXT
status=$(
    if [[ "$success" -eq 1 ]]; then
        echo success
    else
        echo failure
    fi
)
reason=$reason
method=$method
candidate=$candidate
start_x=$sx
start_y=$sy
start_yaw=$yaw
elapsed_sec=$elapsed
finished_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TXT

    if [[ "$success" -eq 1 ]]; then
        echo
        echo "SUCCESS: $method candidate $candidate"
        echo "Elapsed: $elapsed s"
        return 0
    fi

    echo
    echo "FAILURE: $method candidate $candidate"
    echo "Reason : $reason"
    echo "Elapsed: $elapsed s"
    echo "Evidence:"
    tail -80 "$CURRENT_RUN_DIR/logs/A5_agent.log" || true

    return 1
}


preflight

if [[ "$MODE" == "--check" ]]; then
    exit 0
fi


echo
echo "============================================================"
echo "FORMAL PAIRED BATCH STARTING"
echo "============================================================"

mkdir -p "$BATCH_DIR"

cp "$POSES" "$BATCH_DIR/start_poses.csv"

FP_REPRO="$(repo_fingerprint "$REPRO")"
FP_AIMAPP="$(repo_fingerprint "$AIMAPP_RUNTIME")"
FP_SCA="$(repo_fingerprint "$SCA")"

cat > "$BATCH_DIR/source_fingerprints.txt" <<TXT
aimapp_reproduction=$FP_REPRO
aimapp_runtime=$FP_AIMAPP
sca_aifnav=$FP_SCA
TXT

MANIFEST="$BATCH_DIR/pair_manifest.csv"

echo \
"pair_index,candidate,x,y,yaw_rad,aimapp_status,sca_status,pair_status" \
> "$MANIFEST"

PAIRS=0

while IFS=, read -r candidate sx sy yaw clearance finite drift
do
    [[ "$candidate" == "candidate" ]] && continue
    [[ -z "$candidate" ]] && continue

    if (( PAIRS >= TARGET_PAIRS )); then
        break
    fi

    echo
    echo "############################################################"
    echo "CANDIDATE $candidate"
    echo "############################################################"

    if run_one \
        "aimapp_nav2" \
        "$candidate" \
        "$sx" \
        "$sy" \
        "$yaw"
    then
        AIM_STATUS="success"
    else
        AIM_STATUS="failure"
    fi

    if run_one \
        "sca_baseline_nav2" \
        "$candidate" \
        "$sx" \
        "$sy" \
        "$yaw"
    then
        SCA_STATUS="success"
    else
        SCA_STATUS="failure"
    fi

    if [[ \
        "$AIM_STATUS" == "success" \
        && "$SCA_STATUS" == "success" \
    ]]; then
        PAIRS=$((PAIRS + 1))
        PAIR_STATUS="selected"

        echo
        echo "PAIRED SUCCESS $PAIRS/$TARGET_PAIRS"
    else
        PAIR_STATUS="rejected"

        echo
        echo "Candidate $candidate retained as documented failure."
    fi

    echo \
"$PAIRS,$candidate,$sx,$sy,$yaw,$AIM_STATUS,$SCA_STATUS,$PAIR_STATUS" \
        >> "$MANIFEST"

done < "$POSES"


echo
echo "============================================================"
echo "FORMAL BATCH SUMMARY"
echo "============================================================"

cat "$MANIFEST"

echo
echo "Paired successful starts: $PAIRS / $TARGET_PAIRS"
echo "Batch evidence: $BATCH_DIR"

if (( PAIRS < TARGET_PAIRS )); then
    echo
    echo "ERROR:"
    echo "Ten prepared starts were insufficient for five paired successes."
    exit 1
fi

echo
echo "FORMAL MINI WAREHOUSE BATCH COMPLETE"
