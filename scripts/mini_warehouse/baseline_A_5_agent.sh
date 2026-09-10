#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 5
# Run only after Nav2 is active.

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

AIMAPP_SRC="$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/src/aimapp"

# agent_launch.py assumes that <cwd>/tests exists.
mkdir -p "$AIMAPP_SRC/tests"

# Official AIMAPP Python files are not executable in the checked-out repository.
# With --symlink-install the installed executables point directly to these files.
chmod +x \
    "$AIMAPP_SRC/aimapp/aimapp/main.py" \
    "$AIMAPP_SRC/aimapp/aimapp/obs_transf/get_pano_multiple_camera_action.py" \
    "$AIMAPP_SRC/aimapp/aimapp/motion/potential_field_action.py" \
    "$AIMAPP_SRC/aimapp/aimapp/motion/align_odom_to_belief.py"

# This baseline requires Nav2Client to be the active AIMAPP motion client.
if ! grep -Eq '^[[:space:]]*self\.motion_client = Nav2Client\(\)' \
    "$AIMAPP_SRC/aimapp/aimapp/main.py"; then

    echo "ERROR: AIMAPP main.py is not configured to use Nav2Client()."
    echo "Expected:"
    echo "    self.motion_client = Nav2Client()"
    echo "    #self.motion_client = PFClient()"
    exit 1
fi

cd "$AIMAPP_SRC" || exit 1

echo "=========================================="
echo "Baseline A v2 - Terminal 5"
echo "AIMAPP Agent"
echo "Motion layer: Nav2"
echo "=========================================="

exec ros2 launch aimapp agent_launch.py x:=0.0 y:=0.0
