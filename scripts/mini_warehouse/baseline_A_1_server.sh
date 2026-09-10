#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 1
# Order:
# server -> gui -> robot+TF -> Nav2 -> AIMAPP

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

WAREHOUSE_SHARE=$(
    ros2 pkg prefix aws_robomaker_small_warehouse_world
)/share/aws_robomaker_small_warehouse_world

TB3_SHARE=$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo

# Important:
# Keep TurtleBot3 models in GAZEBO_MODEL_PATH.
# Missing this path previously caused several-minute mesh lookup delays.
export GAZEBO_MODEL_PATH="$TB3_SHARE/models:$WAREHOUSE_SHARE/models:$WAREHOUSE_SHARE/worlds:${GAZEBO_MODEL_PATH:-}"

echo "=========================================="
echo "Baseline A v2 - Terminal 1"
echo "Mini Warehouse Gazebo Server"
echo "=========================================="

cd "$WAREHOUSE_SHARE" || exit 1

exec gzserver --verbose \
    -s libgazebo_ros_init.so \
    -s libgazebo_ros_factory.so \
    "$WAREHOUSE_SHARE/worlds/warehouse_mini/warehouse_mini.world"
