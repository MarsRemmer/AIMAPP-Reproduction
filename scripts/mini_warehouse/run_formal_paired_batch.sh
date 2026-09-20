#!/usr/bin/env bash

set -eo pipefail

ROOT="$HOME/SCA-AIFNav-Project"
HARNESS="$ROOT/experiments"
AIMAPP_RUNTIME="$ROOT/aimapp/runtime_ws/src/aimapp"
SCA="$ROOT/sca_aifnav/runtime_ws/src/sca_aifnav"
EXP="$ROOT/results/mini_warehouse"

POSES="$HARNESS/configs/mini_warehouse/start_poses.csv"

TARGET_PAIRS="${TARGET_PAIRS:-3}"

# 200-action smoke timing suggests ~1–2 h/run is plausible.
# Four hours is a conservative safety ceiling, not an experiment metric.
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-14400}"

# External liveness guard only.
#
# This does not define experimental success/failure performance.
# It only aborts a run that has shown no meaningful execution
# progress for an extended period.
NO_PROGRESS_TIMEOUT_SEC="${NO_PROGRESS_TIMEOUT_SEC:-1800}"

# AIMAPP stores a full model.pkl in every step directory.
# Keep periodic checkpoints plus the latest model to prevent
# long formal runs from consuming tens of GB.
AIMAPP_MODEL_KEEP_EVERY="${AIMAPP_MODEL_KEEP_EVERY:-50}"
AIMAPP_MODEL_RETENTION_INTERVAL_SEC="${AIMAPP_MODEL_RETENTION_INTERVAL_SEC:-5}"

COVERAGE_SEMANTICS="${COVERAGE_SEMANTICS:-ever_observed_lidar_cells}"
COVERAGE_RESOLUTION_M="${COVERAGE_RESOLUTION_M:-0.05}"
COVERAGE_MAP_SIZE_M="${COVERAGE_MAP_SIZE_M:-40.0}"
COVERAGE_MAX_RAY_RANGE_M="${COVERAGE_MAX_RAY_RANGE_M:-12.0}"

export COVERAGE_SEMANTICS
export COVERAGE_RESOLUTION_M
export COVERAGE_MAP_SIZE_M
export COVERAGE_MAX_RAY_RANGE_M

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

cd "$HARNESS"

A1="$HARNESS/scripts/mini_warehouse/baseline_A_1_server.sh"
A3="$HARNESS/scripts/mini_warehouse/baseline_A_3_spawn_robot.sh"
A4_AIM="$HARNESS/scripts/mini_warehouse/baseline_A_4_nav2.sh"
A4_SCA="$HARNESS/scripts/mini_warehouse/baseline_S_4_nav2.sh"
A5_AIM="$HARNESS/scripts/mini_warehouse/baseline_A_5_agent.sh"
REC="$HARNESS/scripts/mini_warehouse/common_run_recorder.sh"
COV="$HARNESS/scripts/mini_warehouse/run_coverage_monitor.sh"
COV_PY="$HARNESS/scripts/mini_warehouse/coverage_monitor.py"
VIZ="$HARNESS/scripts/mini_warehouse/run_coverage_visualizer.sh"
VIZ_PY="$HARNESS/scripts/mini_warehouse/coverage_visualizer.py"
RETENTION="$HARNESS/scripts/mini_warehouse/aimapp_model_retention.py"
A5_SCA="$SCA/scripts/mini_warehouse/baseline_A_5_sca.sh"

BATCH_ID="${BATCH_ID:-$(date +%Y%m%d_%H%M%S)}"
BATCH_DIR="$EXP/formal/_batches/$BATCH_ID"

A1_PID=""
A3_PID=""
A4_PID=""
A5_PID=""
REC_PID=""
COV_PID=""
VIZ_PID=""
RETENTION_PID=""

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

    if ! kill -0 -- "-$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        return
    fi

    kill -INT -- "-$pid" 2>/dev/null || true

    for _ in $(seq 1 "$grace")
    do
        if ! kill -0 -- "-$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            return
        fi

        sleep 1
    done

    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 2

    if kill -0 -- "-$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || true
    fi

    wait "$pid" 2>/dev/null || true
}


stop_retention()
{
    if [[ -n "$RETENTION_PID" ]]; then
        stop_group "$RETENTION_PID" 5
        RETENTION_PID=""
    fi

    # One final deterministic prune after AIMAPP has stopped.
    # This guarantees the final latest model is retained and
    # stale intermediate snapshots are removed.
    if [[         "$CURRENT_METHOD" == "aimapp_nav2"         && -n "$CURRENT_RUN_DIR"         && -d "$CURRENT_RUN_DIR/aimapp_native/tests"     ]]; then
        python3 "$RETENTION"             "$CURRENT_RUN_DIR/aimapp_native/tests"             --keep-every "$AIMAPP_MODEL_KEEP_EVERY"             >> "$CURRENT_RUN_DIR/logs/aimapp_model_retention.log"             2>&1             || true
    fi
}


cleanup_current_run()
{
    set +e

    # Finalize visualization while coverage/ROS sources are still alive.
    stop_group "$VIZ_PID" 20
    VIZ_PID=""

    # Finalize coverage while ROS/TF sources are still alive.
    stop_group "$COV_PID" 20
    COV_PID=""

    # Stop rosbag after coverage finalization.
    stop_group "$REC_PID" 20
    REC_PID=""

    stop_group "$A5_PID" 8
    A5_PID=""

    stop_retention

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

    if ! [[ "$NO_PROGRESS_TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: NO_PROGRESS_TIMEOUT_SEC must be a positive integer."
        exit 1
    fi

    echo "Batch ID           : $BATCH_ID"
    echo "Target paired runs : $TARGET_PAIRS"
    echo "Run timeout        : $RUN_TIMEOUT_SEC s"
    echo "No-progress timeout: $NO_PROGRESS_TIMEOUT_SEC s"
    echo "Model keep every   : $AIMAPP_MODEL_KEEP_EVERY steps"
    echo "Retention interval : $AIMAPP_MODEL_RETENTION_INTERVAL_SEC s"
    echo

    for f in \
        "$A1" \
        "$A3" \
        "$A4_AIM" \
        "$A4_SCA" \
        "$A5_AIM" \
        "$REC" \
        "$COV" \
        "$VIZ" \
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

    if [[ ! -f "$COV_PY" ]]; then
        echo "ERROR: missing $COV_PY"
        exit 1
    fi

    if [[ ! -f "$VIZ_PY" ]]; then
        echo "ERROR: missing $VIZ_PY"
        exit 1
    fi

    if [[ ! -f "$RETENTION" ]]; then
        echo "ERROR: missing $RETENTION"
        exit 1
    fi

    python3 - "$RETENTION" <<'PYCODE'
from pathlib import Path
import sys

path = Path(sys.argv[1])
compile(
    path.read_text(encoding="utf-8"),
    str(path),
    "exec",
)

print("AIMAPP retention syntax: PASS")
PYCODE

    if ! grep -q "coverage_exploration.mp4" "$VIZ_PY"; then
        echo "ERROR: coverage visualizer does not create an MP4."
        exit 1
    fi

    if ! grep -q "ever_observed_lidar_cells" "$COV_PY"; then
        echo "ERROR: coverage monitor is not ever-observed."
        exit 1
    fi

    if ! grep -q "COVERAGE_MAP_SIZE_M.*40.0" "$COV"; then
        echo "ERROR: coverage wrapper does not default to 40 m."
        exit 1
    fi

    if ! grep -q "agent/odom|scan|cmd_vel" "$REC"; then
        echo "ERROR: recorder does not preserve raw /scan."
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
    echo "  experiment_harness: $(repo_fingerprint "$HARNESS")"
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


wait_for_coverage_monitor()
{
    local output_dir="$1"

    for _ in $(seq 1 30)
    do
        if [[ -n "$COV_PID" ]] && ! kill -0 "$COV_PID" 2>/dev/null; then
            return 1
        fi

        local topic_ready=0
        local metadata_ready=0

        ros2 topic list 2>/dev/null | grep -qx '/experiment/coverage_stats' \
            && topic_ready=1 || true
        [[ -f "$output_dir/coverage_metadata.json" ]] \
            && metadata_ready=1 || true

        if [[ "$topic_ready" -eq 1 && "$metadata_ready" -eq 1 ]]; then
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

    RETENTION_PID=""

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
        "$HARNESS" \
        "experiment_harness" \
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
    if [[ "$(repo_fingerprint "$HARNESS")" != "$FP_HARNESS" ]]; then
        echo "ERROR: experiment harness source changed during batch."
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
    # A4 / S4 - method-specific Nav2 backend
    # --------------------------------------------------------
    if [[ "$method" == "aimapp_nav2" ]]; then
        A4_RUN="$A4_AIM"
    elif [[ "$method" == "sca_baseline_nav2" ]]; then
        A4_RUN="$A4_SCA"
    else
        echo "ERROR: unknown method $method"
        cleanup_current_run
        return 1
    fi

    echo "Nav2 launcher: $A4_RUN"

    START_X="$sx" \
    START_Y="$sy" \
    START_YAW="$yaw" \
    setsid bash "$A4_RUN" \
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
    # Independent coverage monitor
    # --------------------------------------------------------
    mkdir -p "$CURRENT_RUN_DIR/coverage"

    COVERAGE_SEMANTICS="$COVERAGE_SEMANTICS" \
    COVERAGE_RESOLUTION_M="$COVERAGE_RESOLUTION_M" \
    COVERAGE_MAP_SIZE_M="$COVERAGE_MAP_SIZE_M" \
    COVERAGE_MAX_RAY_RANGE_M="$COVERAGE_MAX_RAY_RANGE_M" \
    setsid bash "$COV" "$CURRENT_RUN_DIR/coverage" \
        > "$CURRENT_RUN_DIR/logs/coverage_monitor.log" \
        2>&1 &

    COV_PID=$!

    if ! wait_for_coverage_monitor "$CURRENT_RUN_DIR/coverage"; then
        echo "ERROR: coverage monitor failed readiness check."
        cat "$CURRENT_RUN_DIR/logs/coverage_monitor.log" || true
        cleanup_current_run
        return 1
    fi

    # --------------------------------------------------------
    # Coverage visualization + video
    # --------------------------------------------------------
    mkdir -p "$CURRENT_RUN_DIR/visualization"

    SHOW=0 \
    setsid bash "$VIZ" "$CURRENT_RUN_DIR/visualization" \
        > "$CURRENT_RUN_DIR/logs/coverage_visualizer.log" \
        2>&1 &

    VIZ_PID=$!

    sleep 3

    if ! kill -0 "$VIZ_PID" 2>/dev/null; then
        echo "WARNING: coverage visualizer exited during startup."
        cat "$CURRENT_RUN_DIR/logs/coverage_visualizer.log" || true
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

        setsid python3 "$RETENTION" \
            "$CURRENT_RUN_DIR/aimapp_native/tests" \
            --keep-every "$AIMAPP_MODEL_KEEP_EVERY" \
            --watch \
            --interval "$AIMAPP_MODEL_RETENTION_INTERVAL_SEC" \
            > "$CURRENT_RUN_DIR/logs/aimapp_model_retention.log" \
            2>&1 &

        RETENTION_PID=$!

        sleep 1

        if ! kill -0 "$RETENTION_PID" 2>/dev/null; then
            echo "ERROR: AIMAPP model retention failed to start."
            cat "$CURRENT_RUN_DIR/logs/aimapp_model_retention.log" || true
            cleanup_current_run
            return 1
        fi

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
    local measurement_status="running"

    local completed=0
    local goals=0

    local progress_value=0
    local last_progress_value=0
    local last_progress_time
    local no_progress_elapsed=0

    local watchdog_log="$CURRENT_RUN_DIR/logs/progress_watchdog.log"

    started="$(date +%s)"
    last_progress_time="$started"
    next_report=60

    cat > "$watchdog_log" <<TXT
method=$method
candidate=$candidate
started_epoch=$started
no_progress_timeout_sec=$NO_PROGRESS_TIMEOUT_SEC
run_timeout_sec=$RUN_TIMEOUT_SEC
TXT

    while true
    do
        now="$(date +%s)"
        elapsed=$((now - started))

        if [[ -n "$COV_PID" ]] && ! kill -0 "$COV_PID" 2>/dev/null; then
            success=0
            reason="coverage_monitor_exited"
            measurement_status="failed"
            break
        fi

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

            progress_value="$completed"

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

            completed="$(
                grep -E \
                    'EXPERIMENT_PROGRESS actions=[0-9]+' \
                    "$CURRENT_RUN_DIR/logs/A5_agent.log" \
                    2>/dev/null \
                | tail -1 \
                | sed -n \
                    's/.*EXPERIMENT_PROGRESS actions=\([0-9][0-9]*\).*/\1/p'
            )"

            completed="${completed:-0}"
            progress_value="$completed"

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

        # ----------------------------------------------------
        # External no-progress watchdog.
        #
        # AIMAPP:
        #   progress_value = completed high-level actions
        #
        # SCA:
        #   progress_value = completed high-level actions
        #   reported by EXPERIMENT_PROGRESS
        # ----------------------------------------------------

        if (( progress_value > last_progress_value )); then
            last_progress_value="$progress_value"
            last_progress_time="$now"

            echo \
                "progress elapsed=${elapsed}s value=${progress_value}" \
                >> "$watchdog_log"
        fi

        no_progress_elapsed=$((now - last_progress_time))

        if (( no_progress_elapsed >= NO_PROGRESS_TIMEOUT_SEC )); then
            success=0
            reason="no_progress_timeout"

            echo \
                "TIMEOUT elapsed=${elapsed}s " \
                "idle=${no_progress_elapsed}s " \
                "last_progress=${last_progress_value}" \
                >> "$watchdog_log"

            break
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
                    "elapsed=${elapsed}s " \
                    "completed=${completed}/200 " \
                    "idle=${no_progress_elapsed}s"
            else
                echo \
                    "[$method candidate $candidate] " \
                    "elapsed=${elapsed}s " \
                    "completed=${completed}/200 " \
                    "idle=${no_progress_elapsed}s"
            fi

            next_report=$((next_report + 60))
        fi

        sleep 10
    done

    # Preserve final messages before finalizing measurement.
    sleep 3

    # Finalize video first while coverage topics still exist.
    stop_group "$VIZ_PID" 20
    VIZ_PID=""

    visualization_status="incomplete"

    if [[ \
        -s "$CURRENT_RUN_DIR/visualization/visualization_summary.json" \
        && -s "$CURRENT_RUN_DIR/visualization/coverage_final.png" \
        && ( \
            -s "$CURRENT_RUN_DIR/visualization/coverage_exploration.mp4" \
            || -s "$CURRENT_RUN_DIR/visualization/coverage_exploration.avi" \
        ) \
    ]]; then
        visualization_status="complete"

        # Frames are only intermediate products. Keep final stills/video.
        rm -rf "$CURRENT_RUN_DIR/visualization/frames"
    else
        echo "WARNING: coverage video output is incomplete."
        cat "$CURRENT_RUN_DIR/logs/coverage_visualizer.log" || true
    fi

    stop_group "$COV_PID" 20
    COV_PID=""

    REQUIRED_COVERAGE_FILES=(
        "$CURRENT_RUN_DIR/coverage/coverage.csv"
        "$CURRENT_RUN_DIR/coverage/coverage_metadata.json"
        "$CURRENT_RUN_DIR/coverage/coverage_summary.json"
        "$CURRENT_RUN_DIR/coverage/coverage_grid.npz"
        "$CURRENT_RUN_DIR/coverage/coverage_map.png"
    )

    measurement_status="complete"

    for coverage_file in "${REQUIRED_COVERAGE_FILES[@]}"
    do
        if [[ ! -s "$coverage_file" ]]; then
            echo "ERROR: missing/empty coverage output: $coverage_file"
            measurement_status="incomplete"
        fi
    done

    if [[ "$measurement_status" != "complete" ]]; then
        success=0
        if [[ "$reason" == "completed_200_actions" ]]; then
            reason="coverage_output_incomplete"
        fi
    fi

    stop_group "$REC_PID" 20
    REC_PID=""

    if [[ -d "$CURRENT_RUN_DIR/rosbag" ]]; then
        ros2 bag info "$CURRENT_RUN_DIR/rosbag" \
            > "$CURRENT_RUN_DIR/rosbag_info.txt" 2>&1 || true
    fi

    stop_group "$A5_PID" 8
    A5_PID=""

    stop_retention

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
measurement_status=$measurement_status
visualization_status=$visualization_status
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

FP_HARNESS="$(repo_fingerprint "$HARNESS")"
FP_AIMAPP="$(repo_fingerprint "$AIMAPP_RUNTIME")"
FP_SCA="$(repo_fingerprint "$SCA")"

cat > "$BATCH_DIR/source_fingerprints.txt" <<TXT
experiment_harness=$FP_HARNESS
aimapp_runtime=$FP_AIMAPP
sca_aifnav=$FP_SCA
TXT

MANIFEST="$BATCH_DIR/pair_manifest.csv"

echo \
"pair_index,candidate,x,y,yaw_rad,aimapp_status,sca_status,pair_status" \
> "$MANIFEST"

RUNS=0

while IFS=, read -r candidate sx sy yaw clearance finite drift
do
    [[ "$candidate" == "candidate" ]] && continue
    [[ -z "$candidate" ]] && continue

    # Fixed experimental design:
    # run exactly the first TARGET_PAIRS prepared start poses.
    # A failure is retained as an experimental result and is NOT
    # replaced by another candidate.
    if (( RUNS >= TARGET_PAIRS )); then
        break
    fi

    RUNS=$((RUNS + 1))

    echo
    echo "############################################################"
    echo "PAIR $RUNS/$TARGET_PAIRS - CANDIDATE $candidate"
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
        PAIR_STATUS="both_success"
    else
        PAIR_STATUS="completed_with_failure"
    fi

    echo
    echo "PAIR COMPLETE $RUNS/$TARGET_PAIRS"
    echo "  candidate : $candidate"
    echo "  AIMAPP    : $AIM_STATUS"
    echo "  SCA-AIFNav: $SCA_STATUS"
    echo "  pair      : $PAIR_STATUS"

    echo \
"$RUNS,$candidate,$sx,$sy,$yaw,$AIM_STATUS,$SCA_STATUS,$PAIR_STATUS" \
        >> "$MANIFEST"

done < "$POSES"


echo
echo "============================================================"
echo "FORMAL BATCH SUMMARY"
echo "============================================================"

cat "$MANIFEST"

echo
echo "Fixed paired starts completed: $RUNS / $TARGET_PAIRS"
echo "Batch evidence: $BATCH_DIR"

if (( RUNS < TARGET_PAIRS )); then
    echo
    echo "ERROR:"
    echo "Prepared start poses were insufficient for the requested fixed runs."
    exit 1
fi

echo
echo "FORMAL MINI WAREHOUSE BATCH COMPLETE"
