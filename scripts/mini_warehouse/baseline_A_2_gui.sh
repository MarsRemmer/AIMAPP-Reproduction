#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 2
# Run after A1 server is running.

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/aimapp_ws/install/setup.bash"

WAREHOUSE_SHARE=$(
    ros2 pkg prefix aws_robomaker_small_warehouse_world
)/share/aws_robomaker_small_warehouse_world

TB3_SHARE=$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo

export GAZEBO_MODEL_PATH="$TB3_SHARE/models:$WAREHOUSE_SHARE/models:$WAREHOUSE_SHARE/worlds:${GAZEBO_MODEL_PATH:-}"

echo "=========================================="
echo "Baseline A v2 - Terminal 2"
echo "Mini Warehouse Gazebo GUI"
echo "=========================================="

cd "$WAREHOUSE_SHARE" || exit 1

exec gzclient
