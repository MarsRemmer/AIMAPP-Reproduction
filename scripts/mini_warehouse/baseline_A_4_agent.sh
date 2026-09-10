#!/usr/bin/env bash

export PYTHONDONTWRITEBYTECODE=1
set +e

source /opt/ros/humble/setup.bash
source "$HOME/aimapp_reproduction_ws/install/setup.bash"

AIMAPP_SRC="$HOME/aimapp_reproduction_ws/src/aimapp"

chmod +x   "$AIMAPP_SRC/aimapp/main.py"   "$AIMAPP_SRC/aimapp/obs_transf/get_pano_multiple_camera_action.py"   "$AIMAPP_SRC/aimapp/motion/potential_field_action.py"   "$AIMAPP_SRC/aimapp/motion/align_odom_to_belief.py"

cd "$AIMAPP_SRC" || exit 1

echo "=========================================="
echo "AIMAPP Mini Warehouse agent"
echo "=========================================="
echo "cwd: $(pwd)"

ros2 launch aimapp agent_launch.py x:=0.0 y:=0.0
