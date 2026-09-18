#!/usr/bin/env bash

# SCA-AIFNav Mini Warehouse
# SCA-specific Nav2 backend
#
# Experiment split:
#   A1 : shared Gazebo server
#   A3 : shared robot + robot_state_publisher
#   S4 : THIS FILE - SCA odom-only Nav2
#   S5 : SCA-AIFNav navigation node
#
# Important:
# - Nav2 global frame is raw physical "odom".
# - No AMCL.
# - No static map.
# - No /initialpose.
# - Global/local costmaps are rolling LiDAR costmaps.
# - SCA converts cognitive targets back to physical odom targets
#   before sending NavigateToPose goals.

set -eo pipefail

export PYTHONDONTWRITEBYTECODE=1

set +u
source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/sca_aifnav/runtime_ws/install/setup.bash"
set -u

SCA_PREFIX="$(ros2 pkg prefix sca_aifnav_sim)"
NAV2_PARAMS="$SCA_PREFIX/share/sca_aifnav_sim/config/nav2_odom_params.yaml"

if [[ ! -f "$NAV2_PARAMS" ]]; then
    echo "ERROR: missing SCA Nav2 parameter file:"
    echo "$NAV2_PARAMS"
    exit 1
fi

if ! grep -q 'global_frame: odom' "$NAV2_PARAMS"; then
    echo "ERROR: SCA Nav2 parameters are not odom-frame navigation."
    exit 1
fi

if grep -q 'static_layer' "$NAV2_PARAMS"; then
    echo "ERROR: unexpected static_layer in SCA odom-only Nav2."
    exit 1
fi

echo "=========================================="
echo "SCA-AIFNav - Terminal S4"
echo "Nav2 backend: odom-only rolling costmaps"
echo "=========================================="
echo "Parameters:"
echo "  $NAV2_PARAMS"
echo
echo "Expected architecture:"
echo "  global_frame = odom"
echo "  rolling costmaps"
echo "  LiDAR obstacle layer"
echo "  NavFn + DWB"
echo "  no AMCL / no static map"
echo

exec ros2 launch nav2_bringup navigation_launch.py \
    use_sim_time:=true \
    autostart:=true \
    params_file:="$NAV2_PARAMS" \
    use_composition:=False \
    use_respawn:=False
