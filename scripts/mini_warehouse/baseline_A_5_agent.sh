#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 5
# Run only after Nav2 is active.

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

START_X="${START_X:-0.0}"
START_Y="${START_Y:-0.0}"
START_YAW="${START_YAW:-0.0}"

AIMAPP_SRC="$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/src/aimapp"

# By default preserve the historical AIMAPP working directory.
#
# Formal experiments can set AIMAPP_RUN_CWD so AIMAPP's native
# tests/<id>/ output is written inside the corresponding experiment
# directory instead of polluting the source tree.
AIMAPP_RUN_CWD="${AIMAPP_RUN_CWD:-$AIMAPP_SRC}"

# agent_launch.py assumes that <cwd>/tests exists.
mkdir -p "$AIMAPP_RUN_CWD/tests"

# AIMAPP is built as a normal CMake install.
# Runtime executables are independent copies and source permissions
# must never be changed by the experiment launcher.
AIMAPP_PREFIX="$(ros2 pkg prefix aimapp)"
AIMAPP_LIBEXEC="$AIMAPP_PREFIX/lib/aimapp"

for executable in main.py get_pano_multiple_camera_action.py potential_field_action.py align_odom_to_belief.py
do
    installed="$AIMAPP_LIBEXEC/$executable"

    if [[ ! -x "$installed" ]]; then
        echo "ERROR: AIMAPP executable unavailable: $installed"
        exit 1
    fi

    if [[ -L "$installed" ]]; then
        echo "ERROR: AIMAPP executable is still a symlink: $installed"
        exit 1
    fi
done

# This baseline requires Nav2Client to be the active AIMAPP motion client.
if ! grep -Eq '^[[:space:]]*self\.motion_client = Nav2Client\(\)' \
    "$AIMAPP_SRC/aimapp/aimapp/main.py"; then

    echo "ERROR: AIMAPP main.py is not configured to use Nav2Client()."
    echo "Expected:"
    echo "    self.motion_client = Nav2Client()"
    echo "    #self.motion_client = PFClient()"
    exit 1
fi

cd "$AIMAPP_RUN_CWD" || exit 1

echo "=========================================="
echo "Baseline A v2 - Terminal 5"
echo "AIMAPP Agent"
echo "Motion layer: Nav2"
echo "Working dir : $AIMAPP_RUN_CWD"
echo "Native data : $AIMAPP_RUN_CWD/tests"
echo "=========================================="

exec ros2 launch aimapp agent_launch.py x:="$START_X" y:="$START_Y"
