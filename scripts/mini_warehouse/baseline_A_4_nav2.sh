#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 4
# Run after A3 has spawned the robot and robot_state_publisher is active.

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/aimapp_ws/install/setup.bash"

echo "=========================================="
echo "Baseline A v2 - Terminal 4"
echo "Nav2"
echo "=========================================="

exec ros2 launch aimapp nav2_humble_launch.py
