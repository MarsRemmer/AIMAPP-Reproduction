#!/usr/bin/env python3
"""
Independent LiDAR-based exploration coverage monitor.

This node is deliberately outside AIMAPP and SCA-AIFNav.

Inputs
------
/odom
    Raw physical odometry from Gazebo.

/scan
    Raw 360-degree planar LiDAR scan.

Outputs
-------
/experiment/coverage_map
    nav_msgs/OccupancyGrid:
        -1 = unknown / fog
         0 = observed free space
       100 = observed obstacle

/experiment/coverage_free_area_m2
/experiment/coverage_known_area_m2
/experiment/coverage_new_free_area_m2
/experiment/distance_m
    Scalar experiment diagnostics.

/experiment/coverage_stats
    JSON summary for rosbag recording.

Files
-----
coverage.csv
coverage_map.png
coverage_summary.json
coverage_metadata.json

The monitor never affects the navigation decision.
"""

import argparse
import csv
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np
import rclpy

from builtin_interfaces.msg import Time as TimeMsg
from nav_msgs.msg import OccupancyGrid, Odometry
from rclpy.duration import Duration
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from rclpy.time import Time
from sensor_msgs.msg import LaserScan
from std_msgs.msg import Float64, String
from tf2_ros import Buffer, TransformException, TransformListener


def quaternion_to_yaw(x, y, z, w):
    """Convert a quaternion to planar yaw."""
    return math.atan2(
        2.0 * (w * z + x * y),
        1.0 - 2.0 * (y * y + z * z),
    )


def bresenham(x0, y0, x1, y1):
    """Yield integer grid cells along one line."""
    x0 = int(x0)
    y0 = int(y0)
    x1 = int(x1)
    y1 = int(y1)

    dx = abs(x1 - x0)
    dy = abs(y1 - y0)

    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1

    error = dx - dy

    while True:
        yield x0, y0

        if x0 == x1 and y0 == y1:
            break

        e2 = 2 * error

        if e2 > -dy:
            error -= dy
            x0 += sx

        if e2 < dx:
            error += dx
            y0 += sy


class CoverageMonitor(Node):
    """Build an experiment-only occupancy/coverage map."""

    def __init__(
        self,
        output_dir,
        resolution,
        map_size_m,
        max_ray_range_m,
        process_period_sec,
        publish_period_sec,
        snapshot_period_sec,
    ):
        super().__init__("experiment_coverage_monitor")

        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        self.resolution = float(resolution)
        self.map_size_m = float(map_size_m)
        self.max_ray_range_m = float(max_ray_range_m)

        self.process_period_sec = float(
            process_period_sec
        )
        self.publish_period_sec = float(
            publish_period_sec
        )
        self.snapshot_period_sec = float(
            snapshot_period_sec
        )

        if self.resolution <= 0.0:
            raise ValueError(
                "resolution must be positive"
            )

        if self.map_size_m <= 0.0:
            raise ValueError(
                "map_size_m must be positive"
            )

        self.width = int(
            math.ceil(
                self.map_size_m
                / self.resolution
            )
        )
        self.height = self.width

        self.origin_x = (
            -0.5 * self.width * self.resolution
        )
        self.origin_y = (
            -0.5 * self.height * self.resolution
        )

        # Sparse sets are used for coverage accounting.
        # This avoids coupling coverage to the visualization format.
        self.free_cells = set()
        self.occupied_cells = set()

        # Canonical exploration state.
        #
        # A cell enters this set as soon as it is directly observed
        # by a valid LiDAR ray. Its later occupancy classification
        # does not change whether it has already been explored.
        #
        # This mirrors AIMAPP's coverage definition based on
        # OccupancyGrid cells whose value is no longer -1.
        self.ever_observed_cells = set()

        # A single noisy LiDAR endpoint must not permanently create
        # an occupied cell. Require repeated hit evidence before an
        # endpoint becomes confirmed occupied.
        #
        # Free ray traversal is considered immediate evidence that
        # a cell has been observed as free.
        self.occupied_hit_threshold = 2
        self.occupied_hit_counts = {}

        # Diagnostic counter for scan-time TF lookup failures.
        self.tf_lookup_failures = 0

        self.latest_odom = None
        self.latest_robot_xy = None
        self.previous_odom_xy = None

        self.distance_m = 0.0

        self.processed_scans = 0
        self.received_scans = 0

        self.last_scan_process_wall = 0.0
        self.last_map_publish_wall = 0.0
        self.last_snapshot_wall = 0.0

        self.start_wall = time.monotonic()

        self._warned_tf_wait = False

        self.tf_buffer = Buffer()

        # TF must be received independently from the monitor's scan
        # callback. Otherwise an exact scan-time lookup can wait for
        # a transform that the same single-threaded executor has not
        # yet had an opportunity to process.
        self.tf_node = Node(
            "experiment_coverage_tf_listener"
        )

        self.tf_listener = TransformListener(
            self.tf_buffer,
            self.tf_node,
            spin_thread=True,
        )

        self.create_subscription(
            Odometry,
            "/odom",
            self._odom_callback,
            qos_profile_sensor_data,
        )

        self.create_subscription(
            LaserScan,
            "/scan",
            self._scan_callback,
            qos_profile_sensor_data,
        )

        self.map_publisher = self.create_publisher(
            OccupancyGrid,
            "/experiment/coverage_map",
            1,
        )

        self.free_area_publisher = (
            self.create_publisher(
                Float64,
                "/experiment/coverage_free_area_m2",
                10,
            )
        )

        self.known_area_publisher = (
            self.create_publisher(
                Float64,
                "/experiment/coverage_known_area_m2",
                10,
            )
        )

        self.new_area_publisher = (
            self.create_publisher(
                Float64,
                "/experiment/coverage_new_free_area_m2",
                10,
            )
        )

        self.new_known_area_publisher = (
            self.create_publisher(
                Float64,
                "/experiment/coverage_new_known_area_m2",
                10,
            )
        )

        self.distance_publisher = (
            self.create_publisher(
                Float64,
                "/experiment/distance_m",
                10,
            )
        )

        self.stats_publisher = self.create_publisher(
            String,
            "/experiment/coverage_stats",
            10,
        )

        self.csv_path = (
            self.output_dir
            / "coverage.csv"
        )

        self.csv_file = self.csv_path.open(
            "w",
            newline="",
            encoding="utf-8",
        )

        self.csv_writer = csv.writer(
            self.csv_file
        )

        self.csv_writer.writerow(
            [
                "elapsed_sec",
                "processed_scan",
                "robot_x",
                "robot_y",
                "sensor_x",
                "sensor_y",
                "sensor_yaw_rad",
                "distance_m",
                "free_cells",
                "occupied_cells",
                "known_cells",
                "free_area_m2",
                "known_area_m2",
                "new_free_cells",
                "new_known_cells",
                "new_free_area_m2",
                "new_known_area_m2",
                "tf_used",
            ]
        )

        self.csv_file.flush()

        metadata = {
            "schema_version": 3,
            "purpose": (
                "independent experiment coverage monitor"
            ),
            "navigation_feedback": False,
            "odom_topic": "/odom",
            "scan_topic": "/scan",
            "map_topic": (
                "/experiment/coverage_map"
            ),
            "map_frame": "odom",
            "canonical_coverage_metric": "known_area_m2",
            "canonical_new_coverage_metric": "new_known_area_m2",
            "tf_timestamp_mode": "scan_header_stamp",
            "tf_listener_mode": "dedicated_thread",
            "occupied_hit_threshold": (
                self.occupied_hit_threshold
            ),
            "resolution_m": self.resolution,
            "map_size_m": self.map_size_m,
            "width_cells": self.width,
            "height_cells": self.height,
            "origin_x": self.origin_x,
            "origin_y": self.origin_y,
            "max_ray_range_m": (
                self.max_ray_range_m
            ),
            "process_period_sec": (
                self.process_period_sec
            ),
            "publish_period_sec": (
                self.publish_period_sec
            ),
            "snapshot_period_sec": (
                self.snapshot_period_sec
            ),
            "coverage_definition": {
                "free_area_m2": (
                    "unique cells observed as free "
                    "* resolution^2"
                ),
                "known_area_m2": (
                    "unique cells directly observed at least once "
                    "by a valid LiDAR ray * resolution^2"
                ),
                "occupancy_classification": (
                    "free, candidate occupied, or confirmed occupied "
                    "is diagnostic and does not determine coverage"
                ),
            },
        }

        with (
            self.output_dir
            / "coverage_metadata.json"
        ).open(
            "w",
            encoding="utf-8",
        ) as file:
            json.dump(
                metadata,
                file,
                indent=2,
                ensure_ascii=False,
            )

        self.get_logger().info(
            "Coverage monitor started: "
            f"{self.width}x{self.height} cells, "
            f"resolution={self.resolution:.3f} m, "
            f"size={self.map_size_m:.1f} m"
        )

    def _odom_callback(
        self,
        message,
    ):
        """Accumulate raw physical travel distance."""
        self.latest_odom = message

        x = float(
            message.pose.pose.position.x
        )
        y = float(
            message.pose.pose.position.y
        )

        self.latest_robot_xy = (
            x,
            y,
        )

        if self.previous_odom_xy is None:
            self.previous_odom_xy = (
                x,
                y,
            )
            return

        px, py = self.previous_odom_xy

        increment = math.hypot(
            x - px,
            y - py,
        )

        # At the robot speeds used here, a single odometry
        # increment should be tiny. Large jumps represent
        # startup/reset artefacts and are deliberately ignored.
        if increment <= 0.50:
            self.distance_m += increment

        self.previous_odom_xy = (
            x,
            y,
        )

    def _scan_sensor_pose(
        self,
        scan,
    ):
        """
        Return LiDAR pose in raw odom frame.

        Prefer TF so the real base_scan translation is included.
        Fall back to the robot-centre odometry pose if TF has not
        become available yet.
        """
        frame_id = (
            scan.header.frame_id
            or "base_scan"
        )

        # IMPORTANT:
        # Transform this LiDAR scan at the instant at which the scan
        # was produced. Using Time() here would request the newest TF
        # and spatially smear walls whenever the robot is moving.
        scan_time = Time.from_msg(
            scan.header.stamp
        )

        try:
            transform = (
                self.tf_buffer.lookup_transform(
                    "odom",
                    frame_id,
                    scan_time,
                    timeout=Duration(
                        seconds=0.20
                    ),
                )
            )

            translation = (
                transform.transform.translation
            )
            rotation = (
                transform.transform.rotation
            )

            yaw = quaternion_to_yaw(
                rotation.x,
                rotation.y,
                rotation.z,
                rotation.w,
            )

            return (
                float(translation.x),
                float(translation.y),
                float(yaw),
                True,
            )

        except TransformException:
            self.tf_lookup_failures += 1

            if not self._warned_tf_wait:
                self.get_logger().warning(
                    "Exact scan-time TF odom->scan unavailable; "
                    "skipping scans until timestamp-aligned TF "
                    "is available"
                )
                self._warned_tf_wait = True

            return None

    def _world_to_grid(
        self,
        x,
        y,
    ):
        gx = math.floor(
            (x - self.origin_x)
            / self.resolution
        )
        gy = math.floor(
            (y - self.origin_y)
            / self.resolution
        )

        return (
            int(gx),
            int(gy),
        )

    def _inside(
        self,
        gx,
        gy,
    ):
        return (
            0 <= gx < self.width
            and 0 <= gy < self.height
        )

    def _mark_free(
        self,
        cell,
    ):
        """
        Record direct free-space evidence.

        Confirmed occupied cells remain occupied. However, free-space
        traversal weakens any still-unconfirmed noisy endpoint evidence.
        """
        self.ever_observed_cells.add(
            cell
        )

        if cell in self.occupied_cells:
            return

        self.free_cells.add(
            cell
        )

        previous_hits = (
            self.occupied_hit_counts.get(
                cell,
                0,
            )
        )

        if previous_hits > 0:
            remaining_hits = (
                previous_hits - 1
            )

            if remaining_hits > 0:
                self.occupied_hit_counts[
                    cell
                ] = remaining_hits
            else:
                self.occupied_hit_counts.pop(
                    cell,
                    None,
                )

    def _mark_occupied(
        self,
        cell,
    ):
        """
        Confirm occupied space only after repeated LiDAR hits.

        One isolated hit is retained only as candidate evidence and
        therefore cannot permanently thicken a wall because of one
        noisy range measurement.
        """
        self.ever_observed_cells.add(
            cell
        )

        hit_count = (
            self.occupied_hit_counts.get(
                cell,
                0,
            )
            + 1
        )

        self.occupied_hit_counts[
            cell
        ] = hit_count

        if (
            hit_count
            < self.occupied_hit_threshold
        ):
            return False

        self.free_cells.discard(
            cell
        )

        self.occupied_cells.add(
            cell
        )

        return True

    def _scan_callback(
        self,
        scan,
    ):
        """Ray-trace one throttled LiDAR scan."""
        self.received_scans += 1

        now = time.monotonic()

        if (
            now - self.last_scan_process_wall
            < self.process_period_sec
        ):
            return

        sensor_pose = (
            self._scan_sensor_pose(
                scan
            )
        )

        if sensor_pose is None:
            return

        self.last_scan_process_wall = now

        sensor_x, sensor_y, sensor_yaw, tf_used = (
            sensor_pose
        )

        start_cell = (
            self._world_to_grid(
                sensor_x,
                sensor_y,
            )
        )

        old_free_count = len(
            self.free_cells
        )

        old_known_count = len(
            self.ever_observed_cells
        )

        scan_max = float(
            scan.range_max
        )

        if not math.isfinite(scan_max):
            scan_max = (
                self.max_ray_range_m
            )

        usable_max = min(
            scan_max,
            self.max_ray_range_m,
        )

        angle = float(
            scan.angle_min
        )

        for measured_range in scan.ranges:
            measured_range = float(
                measured_range
            )

            if math.isnan(
                measured_range
            ):
                angle += float(
                    scan.angle_increment
                )
                continue

            finite_hit = (
                math.isfinite(
                    measured_range
                )
                and measured_range
                >= float(scan.range_min)
                and measured_range
                < usable_max
            )

            if finite_hit:
                ray_length = (
                    measured_range
                )
            else:
                ray_length = (
                    usable_max
                )

            if ray_length <= 0.0:
                angle += float(
                    scan.angle_increment
                )
                continue

            world_angle = (
                sensor_yaw
                + angle
            )

            end_x = (
                sensor_x
                + ray_length
                * math.cos(
                    world_angle
                )
            )
            end_y = (
                sensor_y
                + ray_length
                * math.sin(
                    world_angle
                )
            )

            end_cell = (
                self._world_to_grid(
                    end_x,
                    end_y,
                )
            )

            cells = list(
                bresenham(
                    start_cell[0],
                    start_cell[1],
                    end_cell[0],
                    end_cell[1],
                )
            )

            if finite_hit:
                free_part = cells[:-1]
                occupied_part = cells[-1:]
            else:
                free_part = cells
                occupied_part = []

            for cell in free_part:
                if self._inside(
                    cell[0],
                    cell[1],
                ):
                    self._mark_free(
                        cell
                    )

            for cell in occupied_part:
                if self._inside(
                    cell[0],
                    cell[1],
                ):
                    self._mark_occupied(
                        cell
                    )

            angle += float(
                scan.angle_increment
            )

        self.processed_scans += 1

        free_count = len(
            self.free_cells
        )

        known_count = len(
            self.ever_observed_cells
        )

        occupied_count = len(
            self.occupied_cells
        )

        new_free_cells = (
            free_count
            - old_free_count
        )

        new_known_cells = (
            known_count
            - old_known_count
        )

        cell_area = (
            self.resolution
            * self.resolution
        )

        free_area = (
            free_count
            * cell_area
        )

        known_area = (
            known_count
            * cell_area
        )

        new_free_area = (
            new_free_cells
            * cell_area
        )

        new_known_area = (
            new_known_cells
            * cell_area
        )

        robot_x = math.nan
        robot_y = math.nan

        if self.latest_robot_xy is not None:
            robot_x, robot_y = (
                self.latest_robot_xy
            )

        elapsed = (
            now
            - self.start_wall
        )

        self.csv_writer.writerow(
            [
                f"{elapsed:.6f}",
                self.processed_scans,
                f"{robot_x:.6f}",
                f"{robot_y:.6f}",
                f"{sensor_x:.6f}",
                f"{sensor_y:.6f}",
                f"{sensor_yaw:.9f}",
                f"{self.distance_m:.6f}",
                free_count,
                occupied_count,
                known_count,
                f"{free_area:.6f}",
                f"{known_area:.6f}",
                new_free_cells,
                new_known_cells,
                f"{new_free_area:.6f}",
                f"{new_known_area:.6f}",
                int(tf_used),
            ]
        )

        self.csv_file.flush()

        self._publish_scalar(
            self.free_area_publisher,
            free_area,
        )

        self._publish_scalar(
            self.known_area_publisher,
            known_area,
        )

        self._publish_scalar(
            self.new_area_publisher,
            new_free_area,
        )

        # Canonical exploration increment:
        # newly observed cells, regardless of whether they are
        # free or occupied.
        self._publish_scalar(
            self.new_known_area_publisher,
            new_known_area,
        )

        self._publish_scalar(
            self.distance_publisher,
            self.distance_m,
        )

        stats = {
            "processed_scan": (
                self.processed_scans
            ),
            "distance_m": (
                self.distance_m
            ),
            "free_area_m2": (
                free_area
            ),
            "known_area_m2": (
                known_area
            ),
            "new_free_area_m2": (
                new_free_area
            ),
            "new_known_area_m2": (
                new_known_area
            ),
        }

        message = String()
        message.data = json.dumps(
            stats,
            separators=(",", ":"),
        )

        self.stats_publisher.publish(
            message
        )

        if (
            now - self.last_map_publish_wall
            >= self.publish_period_sec
        ):
            self.publish_map()
            self.last_map_publish_wall = now

        if (
            self.snapshot_period_sec > 0.0
            and (
                now - self.last_snapshot_wall
                >= self.snapshot_period_sec
            )
        ):
            self.save_png()
            self.last_snapshot_wall = now

    @staticmethod
    def _publish_scalar(
        publisher,
        value,
    ):
        message = Float64()
        message.data = float(
            value
        )
        publisher.publish(
            message
        )

    def _occupancy_array(
        self,
    ):
        """Return ROS occupancy values as a flat array."""
        grid = np.full(
            (
                self.height,
                self.width,
            ),
            -1,
            dtype=np.int8,
        )

        for gx, gy in self.ever_observed_cells:
            grid[
                gy,
                gx,
            ] = 50

        for gx, gy in self.free_cells:
            grid[
                gy,
                gx,
            ] = 0

        for gx, gy in self.occupied_cells:
            grid[
                gy,
                gx,
            ] = 100

        return grid

    def publish_map(
        self,
    ):
        """Publish fog/free/occupied occupancy grid."""
        grid = (
            self._occupancy_array()
        )

        message = OccupancyGrid()

        message.header.frame_id = (
            "odom"
        )
        message.header.stamp = (
            self.get_clock()
            .now()
            .to_msg()
        )

        message.info.resolution = (
            self.resolution
        )
        message.info.width = (
            self.width
        )
        message.info.height = (
            self.height
        )

        message.info.origin.position.x = (
            self.origin_x
        )
        message.info.origin.position.y = (
            self.origin_y
        )
        message.info.origin.orientation.w = (
            1.0
        )

        message.data = (
            grid.flatten()
            .astype(np.int8)
            .tolist()
        )

        self.map_publisher.publish(
            message
        )

    def save_png(
        self,
    ):
        """Save a human-readable fog map."""
        image = np.full(
            (
                self.height,
                self.width,
                3,
            ),
            128,
            dtype=np.uint8,
        )

        for gx, gy in self.ever_observed_cells:
            image[
                self.height - 1 - gy,
                gx,
            ] = (
                192,
                192,
                192,
            )

        for gx, gy in self.free_cells:
            image[
                self.height - 1 - gy,
                gx,
            ] = (
                255,
                255,
                255,
            )

        for gx, gy in self.occupied_cells:
            image[
                self.height - 1 - gy,
                gx,
            ] = (
                0,
                0,
                0,
            )

        if self.latest_robot_xy is not None:
            rx, ry = (
                self.latest_robot_xy
            )

            rgx, rgy = (
                self._world_to_grid(
                    rx,
                    ry,
                )
            )

            if self._inside(
                rgx,
                rgy,
            ):
                cv2.circle(
                    image,
                    (
                        rgx,
                        self.height - 1 - rgy,
                    ),
                    4,
                    (
                        0,
                        0,
                        255,
                    ),
                    thickness=-1,
                )

        cv2.imwrite(
            str(
                self.output_dir
                / "coverage_map.png"
            ),
            image,
        )

    def close(
        self,
    ):
        """
        Save final experiment artefacts.

        File finalization must work even after ROS has already
        invalidated its context because SIGINT may shut rclpy down
        before this finally block executes.
        """
        try:
            # Publishing is optional at shutdown. Never let an invalid
            # ROS context prevent persistent experiment files being saved.
            if rclpy.ok():
                try:
                    self.publish_map()
                except Exception as error:
                    print(
                        "WARNING: final ROS map publish failed:",
                        error,
                    )

            self.save_png()

            cell_area = (
                self.resolution
                * self.resolution
            )

            known_cells = len(
                self.ever_observed_cells
            )

            candidate_observed_cells = len(
                self.ever_observed_cells
                - self.free_cells
                - self.occupied_cells
            )

            grid = self._occupancy_array()

            np.savez_compressed(
                self.output_dir
                / "coverage_grid.npz",
                grid=grid,
                known_mask=(
                    grid != -1
                ),
                free_mask=(
                    grid == 0
                ),
                candidate_mask=(
                    grid == 50
                ),
                occupied_mask=(
                    grid == 100
                ),
                resolution_m=np.array(
                    self.resolution
                ),
                origin_x=np.array(
                    self.origin_x
                ),
                origin_y=np.array(
                    self.origin_y
                ),
                map_size_m=np.array(
                    self.map_size_m
                ),
            )

            summary = {
                "coverage_metric": "known_area_m2",
                "coverage_semantics": (
                    "ever_observed_lidar_cells"
                ),
                "processed_scans": (
                    self.processed_scans
                ),
                "received_scans": (
                    self.received_scans
                ),
                "distance_m": (
                    self.distance_m
                ),
                "free_cells": len(
                    self.free_cells
                ),
                "occupied_cells": len(
                    self.occupied_cells
                ),
                "known_cells": (
                    known_cells
                ),
                "ever_observed_cells": (
                    known_cells
                ),
                "candidate_observed_cells": (
                    candidate_observed_cells
                ),
                "free_area_m2": (
                    len(self.free_cells)
                    * cell_area
                ),
                "occupied_area_m2": (
                    len(self.occupied_cells)
                    * cell_area
                ),
                "known_area_m2": (
                    known_cells
                    * cell_area
                ),
                "occupied_hit_threshold": (
                    self.occupied_hit_threshold
                ),
                "unconfirmed_hit_cells": len(
                    self.occupied_hit_counts.keys()
                    - self.occupied_cells
                ),
                "tf_lookup_failures": (
                    self.tf_lookup_failures
                ),
                "tf_timestamp_mode": (
                    "scan_header_stamp"
                ),
                "tf_listener_mode": (
                    "dedicated_thread"
                ),
            }

            with (
                self.output_dir
                / "coverage_summary.json"
            ).open(
                "w",
                encoding="utf-8",
            ) as file:
                json.dump(
                    summary,
                    file,
                    indent=2,
                    ensure_ascii=False,
                )

            message = (
                "Coverage monitor finished: "
                f"known={summary['known_area_m2']:.3f} m^2, "
                f"free={summary['free_area_m2']:.3f} m^2, "
                f"distance={summary['distance_m']:.3f} m"
            )

            if rclpy.ok():
                self.get_logger().info(
                    message
                )
            else:
                print(
                    message
                )

        finally:
            if not self.csv_file.closed:
                self.csv_file.flush()
                self.csv_file.close()

            # TransformListener owns a dedicated executor thread in V3.1.
            # Stop it explicitly so no helper process survives into the
            # next experiment.
            try:
                if hasattr(
                    self,
                    "tf_listener",
                ):
                    self.tf_listener.unregister()
            except Exception as error:
                print(
                    "WARNING: TF listener shutdown failed:",
                    error,
                )

            try:
                if hasattr(
                    self,
                    "tf_node",
                ):
                    self.tf_node.destroy_node()
            except Exception as error:
                print(
                    "WARNING: TF helper node shutdown failed:",
                    error,
                )


def parse_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    parser.add_argument(
        "--resolution",
        type=float,
        default=0.05,
    )

    parser.add_argument(
        "--map-size-m",
        type=float,
        default=20.0,
    )

    parser.add_argument(
        "--max-ray-range-m",
        type=float,
        default=12.0,
    )

    parser.add_argument(
        "--process-period-sec",
        type=float,
        default=0.5,
    )

    parser.add_argument(
        "--publish-period-sec",
        type=float,
        default=2.0,
    )

    parser.add_argument(
        "--snapshot-period-sec",
        type=float,
        default=30.0,
    )

    return parser.parse_known_args()


def main():
    args, ros_args = (
        parse_arguments()
    )

    rclpy.init(
        args=ros_args
    )

    node = CoverageMonitor(
        output_dir=(
            args.output_dir
        ),
        resolution=(
            args.resolution
        ),
        map_size_m=(
            args.map_size_m
        ),
        max_ray_range_m=(
            args.max_ray_range_m
        ),
        process_period_sec=(
            args.process_period_sec
        ),
        publish_period_sec=(
            args.publish_period_sec
        ),
        snapshot_period_sec=(
            args.snapshot_period_sec
        ),
    )

    try:
        rclpy.spin(
            node
        )
    except (
        KeyboardInterrupt,
        ExternalShutdownException,
    ):
        pass
    finally:
        node.close()

        try:
            node.destroy_node()
        except Exception:
            pass

        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
