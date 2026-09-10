#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A - Terminal 2
# Run after baseline_A_1_server.sh has started.

export PYTHONDONTWRITEBYTECODE=1
set +e

source /opt/ros/humble/setup.bash
source "$HOME/aimapp_reproduction_ws/install/setup.bash"

WAREHOUSE_SHARE=$(
    ros2 pkg prefix aws_robomaker_small_warehouse_world
)/share/aws_robomaker_small_warehouse_world

TB3_SHARE=$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo

export GAZEBO_MODEL_PATH="$TB3_SHARE/models:$WAREHOUSE_SHARE/models:$WAREHOUSE_SHARE/worlds"

cd "$WAREHOUSE_SHARE" || exit 1

gzclient
