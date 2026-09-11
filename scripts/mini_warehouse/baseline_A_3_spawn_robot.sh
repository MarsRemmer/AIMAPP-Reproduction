#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A v2 - Terminal 3
#
# 1. Spawn AIMAPP waffle_pi_plus model
# 2. Start robot_state_publisher
#
# robot_state_publisher is required to provide:
# base_footprint -> base_link
# so Nav2 can construct:
# odom -> base_footprint -> base_link

export PYTHONDONTWRITEBYTECODE=1
set -e

source /opt/ros/humble/setup.bash
source "$HOME/SCA-AIFNav-Project/aimapp/runtime_ws/install/setup.bash"

START_X="${START_X:-0.0}"
START_Y="${START_Y:-0.0}"
START_YAW="${START_YAW:-0.0}"

TB3_SHARE=$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo

TB3_DESC=$(
    ros2 pkg prefix turtlebot3_description
)/share/turtlebot3_description

MODEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/gazebo_models/turtlebot3_waffle_pi_plus/model.sdf"
URDF="$TB3_DESC/urdf/turtlebot3_waffle_pi.urdf"

echo "=========================================="
echo "Baseline A v2 - Terminal 3"
echo "Spawn waffle_pi_plus + publish robot TF"
echo "MODEL=$MODEL"
echo "URDF=$URDF"
echo "=========================================="

ros2 run gazebo_ros spawn_entity.py \
    -entity waffle_pi_plus \
    -file "$MODEL" \
    -x "$START_X" \
    -y "$START_Y" \
    -z 0.01 \
    -Y "$START_YAW"

echo
echo "Robot spawned successfully."
echo "Starting robot_state_publisher..."

# The TurtleBot3 .urdf still contains xacro expressions.
# It must be expanded before passing to robot_state_publisher.
ROBOT_DESC="$(xacro "$URDF")"

exec ros2 run robot_state_publisher robot_state_publisher \
    --ros-args \
    -p use_sim_time:=true \
    -p robot_description:="$ROBOT_DESC"
