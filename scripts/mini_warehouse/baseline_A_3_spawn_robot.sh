#!/usr/bin/env bash

# AIMAPP Mini Warehouse
# Baseline A - Terminal 3
# Run after Mini Warehouse is visible in gzclient.

export PYTHONDONTWRITEBYTECODE=1
set +e

source /opt/ros/humble/setup.bash
source "$HOME/aimapp_reproduction_ws/install/setup.bash"

TB3_SHARE=$(
    ros2 pkg prefix turtlebot3_gazebo
)/share/turtlebot3_gazebo

MODEL="$TB3_SHARE/models/turtlebot3_waffle_pi_plus/model.sdf"

echo "=========================================="
echo "Baseline A: GUI already running -> Spawn"
echo "MODEL=$MODEL"
echo "=========================================="

/usr/bin/time \
    -f $'\nBASELINE_A_SPAWN_TIME=%e seconds' \
    ros2 run gazebo_ros spawn_entity.py \
        -entity waffle_pi_plus \
        -file "$MODEL" \
        -x 0.0 \
        -y 0.0 \
        -z 0.01
