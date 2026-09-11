#!/usr/bin/env python3
"""Build a LiDAR-observable reference coverage map for Mini Warehouse."""

import argparse
import csv
import json
import math
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import rclpy
from gazebo_msgs.msg import EntityState
from gazebo_msgs.srv import GetEntityState, SetEntityState
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import LaserScan


ROBOT_ENTITY = "waffle_pi_plus"


def quaternion_to_yaw(
    quaternion,
):
    """Convert one geometry quaternion to planar yaw."""
    siny_cosp = (
        2.0
        * (
            quaternion.w
            * quaternion.z
            + quaternion.x
            * quaternion.y
        )
    )

    cosy_cosp = (
        1.0
        - 2.0
        * (
            quaternion.y
            * quaternion.y
            + quaternion.z
            * quaternion.z
        )
    )

    return math.atan2(
        siny_cosp,
        cosy_cosp,
    )


def bresenham(
    x0,
    y0,
    x1,
    y1,
):
    """Yield integer cells along one grid ray."""
    x0 = int(x0)
    y0 = int(y0)
    x1 = int(x1)
    y1 = int(y1)

    dx = abs(x1 - x0)
    dy = abs(y1 - y0)

    sx = (
        1
        if x0 < x1
        else -1
    )

    sy = (
        1
        if y0 < y1
        else -1
    )

    error = dx - dy

    while True:
        yield x0, y0

        if (
            x0 == x1
            and y0 == y1
        ):
            break

        e2 = 2 * error

        if e2 > -dy:
            error -= dy
            x0 += sx

        if e2 < dx:
            error += dx
            y0 += sy


class ReferenceCoverageProbe(Node):
    """Probe Gazebo poses and acquire corresponding LiDAR scans."""

    def __init__(self):
        """Create subscriptions and Gazebo state clients."""
        super().__init__(
            "reference_coverage_probe_v4"
        )

        self.scan = None
        self.scan_revision = 0

        self.sensor_entity_name = None

        self.create_subscription(
            LaserScan,
            "/scan",
            self._scan_callback,
            qos_profile_sensor_data,
        )

        self.set_client = self.create_client(
            SetEntityState,
            "/gazebo/set_entity_state",
        )

        self.get_client = self.create_client(
            GetEntityState,
            "/gazebo/get_entity_state",
        )

    def _scan_callback(
        self,
        message,
    ):
        """Store the newest scan and increase its revision."""
        self.scan = message
        self.scan_revision += 1

    def wait_services(
        self,
    ):
        """Wait for Gazebo state services."""
        if not self.set_client.wait_for_service(
            timeout_sec=15.0
        ):
            raise RuntimeError(
                "/gazebo/set_entity_state unavailable"
            )

        if not self.get_client.wait_for_service(
            timeout_sec=15.0
        ):
            raise RuntimeError(
                "/gazebo/get_entity_state unavailable"
            )

    def call(
        self,
        client,
        request,
        timeout=5.0,
    ):
        """Call one ROS service synchronously with timeout."""
        future = client.call_async(
            request
        )

        deadline = (
            time.monotonic()
            + timeout
        )

        while (
            rclpy.ok()
            and not future.done()
        ):
            rclpy.spin_once(
                self,
                timeout_sec=0.05,
            )

            if (
                time.monotonic()
                > deadline
            ):
                raise TimeoutError(
                    "Gazebo service call timed out"
                )

        return future.result()

    def teleport(
        self,
        x,
        y,
        yaw,
        z,
    ):
        """Teleport the robot model to one candidate pose."""
        request = SetEntityState.Request()

        state = EntityState()

        state.name = ROBOT_ENTITY
        state.reference_frame = "world"

        state.pose.position.x = float(x)
        state.pose.position.y = float(y)
        state.pose.position.z = float(z)

        state.pose.orientation.z = (
            math.sin(
                yaw / 2.0
            )
        )

        state.pose.orientation.w = (
            math.cos(
                yaw / 2.0
            )
        )

        request.state = state

        result = self.call(
            self.set_client,
            request,
        )

        return bool(
            result is not None
            and result.success
        )

    def entity_state(
        self,
        name,
    ):
        """Return one Gazebo entity pose in world coordinates."""
        request = GetEntityState.Request()

        request.name = name
        request.reference_frame = "world"

        result = self.call(
            self.get_client,
            request,
        )

        if (
            result is None
            or not result.success
        ):
            return None

        pose = result.state.pose

        return (
            float(
                pose.position.x
            ),
            float(
                pose.position.y
            ),
            float(
                pose.position.z
            ),
            float(
                quaternion_to_yaw(
                    pose.orientation
                )
            ),
        )

    def robot_state(
        self,
    ):
        """Return physical robot model pose."""
        return self.entity_state(
            ROBOT_ENTITY
        )

    def sensor_state(
        self,
        scan,
    ):
        """
        Return physical LiDAR pose from Gazebo.

        The runtime monitor uses odom->scan TF. During this isolated
        Gazebo probe there is no guarantee that robot_state_publisher
        exists, so V4 resolves the scan-frame link directly from Gazebo.
        """
        frame = (
            scan.header.frame_id
            or "base_scan"
        ).strip("/")

        if self.sensor_entity_name is not None:
            result = self.entity_state(
                self.sensor_entity_name
            )

            if result is not None:
                return (
                    result,
                    self.sensor_entity_name,
                )

            self.sensor_entity_name = None

        normalized = frame.replace(
            "/",
            "::",
        )

        candidates = []

        if normalized.startswith(
            ROBOT_ENTITY + "::"
        ):
            candidates.append(
                normalized
            )
        else:
            candidates.append(
                f"{ROBOT_ENTITY}::{normalized}"
            )

        # Common fallback link names used by TurtleBot3 SDF variants.
        for link_name in (
            "base_scan",
            "base_scan_link",
            "lidar_link",
            "laser_link",
        ):
            candidates.append(
                f"{ROBOT_ENTITY}::{link_name}"
            )

        unique_candidates = []

        for candidate in candidates:
            if (
                candidate
                not in unique_candidates
            ):
                unique_candidates.append(
                    candidate
                )

        for candidate in unique_candidates:
            result = self.entity_state(
                candidate
            )

            if result is not None:
                self.sensor_entity_name = (
                    candidate
                )

                self.get_logger().info(
                    "Resolved LiDAR Gazebo entity: "
                    f"{candidate}"
                )

                return (
                    result,
                    candidate,
                )

        raise RuntimeError(
            "Cannot resolve physical LiDAR entity for "
            f"scan frame '{frame}'. Tried: "
            + ", ".join(
                unique_candidates
            )
        )

    def fresh_scan_after(
        self,
        previous_revision,
        timeout=1.5,
    ):
        """Return the first available scan newer than one revision."""
        deadline = (
            time.monotonic()
            + timeout
        )

        while rclpy.ok():
            rclpy.spin_once(
                self,
                timeout_sec=0.05,
            )

            if (
                self.scan is not None
                and self.scan_revision
                > previous_revision
            ):
                return self.scan

            if (
                time.monotonic()
                > deadline
            ):
                return None

        return None


def scan_metrics(
    scan,
):
    """Return finite-hit count and minimum valid range."""
    if scan is None:
        return None

    ranges = np.asarray(
        scan.ranges,
        dtype=float,
    )

    valid = (
        np.isfinite(
            ranges
        )
        & (
            ranges
            >= float(
                scan.range_min
            )
        )
        & (
            ranges
            <= float(
                scan.range_max
            )
        )
    )

    finite = ranges[
        valid
    ]

    if len(finite) == 0:
        return {
            "finite_count": 0,
            "min_range": math.inf,
        }

    return {
        "finite_count": int(
            len(finite)
        ),
        "min_range": float(
            np.min(
                finite
            )
        ),
    }


def snapshot_scan(
    scan,
):
    """Copy only the scan fields required by the offline evaluator."""
    return {
        "ranges": np.asarray(
            scan.ranges,
            dtype=float,
        ).copy(),
        "angle_min": float(
            scan.angle_min
        ),
        "angle_increment": float(
            scan.angle_increment
        ),
        "range_min": float(
            scan.range_min
        ),
        "range_max": float(
            scan.range_max
        ),
        "frame_id": str(
            scan.header.frame_id
        ),
    }


def connected_component(
    valid_records,
    coordinates,
):
    """
    Return the collision-valid component connected to the origin.

    Diagonal adjacency is allowed only when both orthogonal neighbours
    are valid, preventing artificial corner cutting through walls.
    """
    if not valid_records:
        return set(), None

    seed = min(
        valid_records,
        key=lambda key: (
            coordinates[key[0]]
            * coordinates[key[0]]
            + coordinates[key[1]]
            * coordinates[key[1]]
        ),
    )

    queue = deque(
        [seed]
    )

    connected = {
        seed
    }

    axial = (
        (-1, 0),
        (1, 0),
        (0, -1),
        (0, 1),
    )

    diagonal = (
        (-1, -1),
        (-1, 1),
        (1, -1),
        (1, 1),
    )

    while queue:
        ix, iy = queue.popleft()

        for dx, dy in axial:
            candidate = (
                ix + dx,
                iy + dy,
            )

            if (
                candidate in valid_records
                and candidate not in connected
            ):
                connected.add(
                    candidate
                )
                queue.append(
                    candidate
                )

        for dx, dy in diagonal:
            candidate = (
                ix + dx,
                iy + dy,
            )

            if (
                candidate not in valid_records
                or candidate in connected
            ):
                continue

            side_a = (
                ix + dx,
                iy,
            )

            side_b = (
                ix,
                iy + dy,
            )

            if (
                side_a not in valid_records
                or side_b not in valid_records
            ):
                continue

            connected.add(
                candidate
            )
            queue.append(
                candidate
            )

    return connected, seed


def main():
    """Run dense Gazebo probing and build the V4 reference map."""
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    parser.add_argument(
        "--min-coordinate",
        type=float,
        default=-3.0,
    )

    parser.add_argument(
        "--max-coordinate",
        type=float,
        default=3.0,
    )

    parser.add_argument(
        "--step",
        type=float,
        default=0.25,
    )

    parser.add_argument(
        "--minimum-clearance",
        type=float,
        default=0.35,
    )

    parser.add_argument(
        "--resolution",
        type=float,
        default=0.05,
    )

    parser.add_argument(
        "--map-size-m",
        type=float,
        default=40.0,
    )

    parser.add_argument(
        "--max-ray-range-m",
        type=float,
        default=12.0,
    )

    parser.add_argument(
        "--occupied-hit-threshold",
        type=int,
        default=2,
    )

    args = parser.parse_args()

    if args.step <= 0.0:
        raise ValueError(
            "step must be positive"
        )

    if args.resolution <= 0.0:
        raise ValueError(
            "resolution must be positive"
        )

    if args.map_size_m <= 0.0:
        raise ValueError(
            "map-size-m must be positive"
        )

    if (
        args.occupied_hit_threshold
        <= 0
    ):
        raise ValueError(
            "occupied-hit-threshold must be positive"
        )

    output = Path(
        args.output_dir
    )

    output.mkdir(
        parents=True,
        exist_ok=True,
    )

    width = int(
        math.ceil(
            args.map_size_m
            / args.resolution
        )
    )

    height = width

    origin_x = (
        -0.5
        * width
        * args.resolution
    )

    origin_y = (
        -0.5
        * height
        * args.resolution
    )

    free_cells = set()
    occupied_cells = set()

    # Canonical coverage: every grid cell directly observed at least
    # once by a valid LiDAR ray, independently of its later occupancy
    # classification.
    ever_observed_cells = set()

    occupied_hit_counts = {}

    clipped_ray_endpoints = 0

    def world_to_grid(
        x,
        y,
    ):
        return (
            int(
                math.floor(
                    (
                        x
                        - origin_x
                    )
                    / args.resolution
                )
            ),
            int(
                math.floor(
                    (
                        y
                        - origin_y
                    )
                    / args.resolution
                )
            ),
        )

    def inside(
        gx,
        gy,
    ):
        return (
            0 <= gx < width
            and 0 <= gy < height
        )

    def mark_free(
        cell,
    ):
        # Match the runtime evaluator.
        ever_observed_cells.add(
            cell
        )

        if cell in occupied_cells:
            return

        free_cells.add(
            cell
        )

        previous_hits = (
            occupied_hit_counts.get(
                cell,
                0,
            )
        )

        if previous_hits > 0:
            remaining_hits = (
                previous_hits
                - 1
            )

            if remaining_hits > 0:
                occupied_hit_counts[
                    cell
                ] = remaining_hits
            else:
                occupied_hit_counts.pop(
                    cell,
                    None,
                )

    def mark_occupied(
        cell,
    ):
        # Occupancy confidence is separate from coverage.
        ever_observed_cells.add(
            cell
        )

        hit_count = (
            occupied_hit_counts.get(
                cell,
                0,
            )
            + 1
        )

        occupied_hit_counts[
            cell
        ] = hit_count

        if (
            hit_count
            < args.occupied_hit_threshold
        ):
            return False

        free_cells.discard(
            cell
        )

        occupied_cells.add(
            cell
        )

        return True

    def integrate_scan(
        scan,
        sensor_x,
        sensor_y,
        sensor_yaw,
    ):
        nonlocal clipped_ray_endpoints

        start_cell = world_to_grid(
            sensor_x,
            sensor_y,
        )

        scan_max = float(
            scan["range_max"]
        )

        if not math.isfinite(
            scan_max
        ):
            scan_max = (
                args.max_ray_range_m
            )

        usable_max = min(
            scan_max,
            args.max_ray_range_m,
        )

        angle = float(
            scan["angle_min"]
        )

        for measured_range in scan[
            "ranges"
        ]:
            measured_range = float(
                measured_range
            )

            if math.isnan(
                measured_range
            ):
                angle += float(
                    scan[
                        "angle_increment"
                    ]
                )
                continue

            finite_hit = (
                math.isfinite(
                    measured_range
                )
                and measured_range
                >= float(
                    scan[
                        "range_min"
                    ]
                )
                and measured_range
                < usable_max
            )

            ray_length = (
                measured_range
                if finite_hit
                else usable_max
            )

            if ray_length <= 0.0:
                angle += float(
                    scan[
                        "angle_increment"
                    ]
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

            end_cell = world_to_grid(
                end_x,
                end_y,
            )

            if not inside(
                end_cell[0],
                end_cell[1],
            ):
                clipped_ray_endpoints += 1

            cells = list(
                bresenham(
                    start_cell[0],
                    start_cell[1],
                    end_cell[0],
                    end_cell[1],
                )
            )

            if finite_hit:
                free_part = (
                    cells[:-1]
                )
                occupied_part = (
                    cells[-1:]
                )
            else:
                free_part = cells
                occupied_part = []

            for cell in free_part:
                if inside(
                    cell[0],
                    cell[1],
                ):
                    mark_free(
                        cell
                    )

            for cell in occupied_part:
                if inside(
                    cell[0],
                    cell[1],
                ):
                    mark_occupied(
                        cell
                    )

            angle += float(
                scan[
                    "angle_increment"
                ]
            )

    rclpy.init()

    node = ReferenceCoverageProbe()

    all_probe_rows = []

    try:
        node.wait_services()

        print(
            "Calibrating Mini Warehouse floor..."
        )

        end = (
            time.monotonic()
            + 2.0
        )

        while (
            time.monotonic()
            < end
        ):
            rclpy.spin_once(
                node,
                timeout_sec=0.05,
            )

        reference = (
            node.robot_state()
        )

        if reference is None:
            raise RuntimeError(
                "Cannot obtain reference robot pose"
            )

        (
            _,
            _,
            reference_z,
            _,
        ) = reference

        print(
            f"reference z = "
            f"{reference_z:.3f}"
        )

        coordinates = np.arange(
            args.min_coordinate,
            args.max_coordinate
            + args.step / 2.0,
            args.step,
        )

        total = (
            len(coordinates)
            ** 2
        )

        valid_records = {}

        tested = 0

        print(
            f"candidate grid = "
            f"{len(coordinates)} x "
            f"{len(coordinates)} = "
            f"{total}"
        )

        print(
            "Phase A: probing collision-valid poses..."
        )

        for ix, x in enumerate(
            coordinates
        ):
            for iy, y in enumerate(
                coordinates
            ):
                tested += 1

                previous_revision = (
                    node.scan_revision
                )

                teleport_ok = (
                    node.teleport(
                        float(x),
                        float(y),
                        0.0,
                        reference_z,
                    )
                )

                if not teleport_ok:
                    all_probe_rows.append(
                        (
                            float(x),
                            float(y),
                            math.nan,
                            math.nan,
                            math.nan,
                            0,
                            math.nan,
                            0,
                            0,
                            "",
                        )
                    )
                    continue

                settle_end = (
                    time.monotonic()
                    + 0.30
                )

                while (
                    time.monotonic()
                    < settle_end
                ):
                    rclpy.spin_once(
                        node,
                        timeout_sec=0.05,
                    )

                scan = (
                    node.fresh_scan_after(
                        previous_revision,
                        timeout=1.0,
                    )
                )

                robot_state = (
                    node.robot_state()
                )

                metrics = (
                    scan_metrics(
                        scan
                    )
                )

                if (
                    scan is None
                    or robot_state is None
                    or metrics is None
                ):
                    all_probe_rows.append(
                        (
                            float(x),
                            float(y),
                            math.nan,
                            math.nan,
                            math.nan,
                            0,
                            math.nan,
                            0,
                            0,
                            "",
                        )
                    )
                    continue

                (
                    px,
                    py,
                    pz,
                    yaw,
                ) = robot_state

                drift = math.hypot(
                    px - float(x),
                    py - float(y),
                )

                dz = abs(
                    pz
                    - reference_z
                )

                # Mini Warehouse is much smaller than the 12 m sensor
                # range. A valid interior pose should therefore see at
                # least one finite obstacle return.
                lidar_clear = (
                    metrics[
                        "finite_count"
                    ] > 0
                    and metrics[
                        "min_range"
                    ]
                    >= args.minimum_clearance
                )

                valid = (
                    drift <= 0.12
                    and dz <= 0.10
                    and lidar_clear
                )

                sensor_entity = ""

                if valid:
                    (
                        sensor_state,
                        sensor_entity,
                    ) = node.sensor_state(
                        scan
                    )

                    (
                        sensor_x,
                        sensor_y,
                        sensor_z,
                        sensor_yaw,
                    ) = sensor_state

                    valid_records[
                        (ix, iy)
                    ] = {
                        "requested_x": float(
                            x
                        ),
                        "requested_y": float(
                            y
                        ),
                        "robot_x": px,
                        "robot_y": py,
                        "robot_z": pz,
                        "robot_yaw": yaw,
                        "sensor_x": sensor_x,
                        "sensor_y": sensor_y,
                        "sensor_z": sensor_z,
                        "sensor_yaw": sensor_yaw,
                        "sensor_entity": (
                            sensor_entity
                        ),
                        "min_range": (
                            metrics[
                                "min_range"
                            ]
                        ),
                        "finite_count": (
                            metrics[
                                "finite_count"
                            ]
                        ),
                        "scan": snapshot_scan(
                            scan
                        ),
                    }

                all_probe_rows.append(
                    (
                        float(x),
                        float(y),
                        px,
                        py,
                        drift,
                        metrics[
                            "finite_count"
                        ],
                        metrics[
                            "min_range"
                        ],
                        int(valid),
                        0,
                        sensor_entity,
                    )
                )

                if (
                    tested % 25 == 0
                    or tested == total
                ):
                    print(
                        f"{tested:4d}/{total} "
                        f"tested | "
                        f"locally-valid="
                        f"{len(valid_records):3d}"
                    )

        print()
        print(
            "Phase B: extracting origin-connected component..."
        )

        (
            connected,
            seed,
        ) = connected_component(
            valid_records,
            coordinates,
        )

        if not connected:
            raise RuntimeError(
                "No origin-connected valid probe component found"
            )

        disconnected = (
            set(
                valid_records
            )
            - connected
        )

        seed_xy = (
            coordinates[
                seed[0]
            ],
            coordinates[
                seed[1]
            ],
        )

        print(
            f"seed index       = {seed}"
        )

        print(
            f"seed position    = "
            f"({seed_xy[0]:.3f}, "
            f"{seed_xy[1]:.3f})"
        )

        print(
            f"locally valid    = "
            f"{len(valid_records)}"
        )

        print(
            f"connected valid  = "
            f"{len(connected)}"
        )

        print(
            f"disconnected     = "
            f"{len(disconnected)}"
        )

        print()
        print(
            "Phase C: integrating connected scans "
            "with V3.1 occupancy semantics..."
        )

        accepted_records = []

        for sequence, key in enumerate(
            sorted(
                connected
            ),
            start=1,
        ):
            record = (
                valid_records[
                    key
                ]
            )

            before = len(
                ever_observed_cells
            )

            integrate_scan(
                record["scan"],
                record["sensor_x"],
                record["sensor_y"],
                record["sensor_yaw"],
            )

            after = len(
                ever_observed_cells
            )

            accepted_records.append(
                (
                    sequence,
                    key[0],
                    key[1],
                    record[
                        "requested_x"
                    ],
                    record[
                        "requested_y"
                    ],
                    record[
                        "robot_x"
                    ],
                    record[
                        "robot_y"
                    ],
                    record[
                        "sensor_x"
                    ],
                    record[
                        "sensor_y"
                    ],
                    record[
                        "sensor_yaw"
                    ],
                    record[
                        "min_range"
                    ],
                    record[
                        "finite_count"
                    ],
                    record[
                        "sensor_entity"
                    ],
                    after - before,
                    after,
                )
            )

        known_cells = set(
            ever_observed_cells
        )

        candidate_observed_cells = (
            ever_observed_cells
            - free_cells
            - occupied_cells
        )

        cell_area = (
            args.resolution
            * args.resolution
        )

        known_area = (
            len(
                known_cells
            )
            * cell_area
        )

        free_area = (
            len(
                free_cells
            )
            * cell_area
        )

        occupied_area = (
            len(
                occupied_cells
            )
            * cell_area
        )

        grid = np.full(
            (
                height,
                width,
            ),
            -1,
            dtype=np.int8,
        )

        for gx, gy in ever_observed_cells:
            grid[
                gy,
                gx,
            ] = 50

        for gx, gy in free_cells:
            grid[
                gy,
                gx,
            ] = 0

        for gx, gy in occupied_cells:
            grid[
                gy,
                gx,
            ] = 100

        free_mask = (
            grid == 0
        )

        candidate_mask = (
            grid == 50
        )

        occupied_mask = (
            grid == 100
        )

        known_mask = (
            grid != -1
        )

        np.save(
            output
            / "reference_coverage_grid.npy",
            grid,
        )

        np.savez_compressed(
            output
            / "reference_coverage_grid_v4.npz",
            grid=grid,
            free_mask=free_mask,
            candidate_mask=candidate_mask,
            occupied_mask=occupied_mask,
            known_mask=known_mask,
            resolution_m=np.array(
                args.resolution
            ),
            origin_x=np.array(
                origin_x
            ),
            origin_y=np.array(
                origin_y
            ),
            map_size_m=np.array(
                args.map_size_m
            ),
        )

        image = np.full(
            (
                height,
                width,
                3,
            ),
            128,
            dtype=np.uint8,
        )

        for gx, gy in ever_observed_cells:
            image[
                height - 1 - gy,
                gx,
            ] = (
                192,
                192,
                192,
            )

        for gx, gy in free_cells:
            image[
                height - 1 - gy,
                gx,
            ] = (
                255,
                255,
                255,
            )

        for gx, gy in occupied_cells:
            image[
                height - 1 - gy,
                gx,
            ] = (
                0,
                0,
                0,
            )

        cv2.imwrite(
            str(
                output
                / "reference_coverage_map.png"
            ),
            image,
        )

        with (
            output
            / "accepted_probe_poses.csv"
        ).open(
            "w",
            newline="",
            encoding="utf-8",
        ) as f:
            writer = csv.writer(
                f
            )

            writer.writerow(
                [
                    "sequence",
                    "grid_ix",
                    "grid_iy",
                    "requested_x",
                    "requested_y",
                    "robot_x",
                    "robot_y",
                    "sensor_x",
                    "sensor_y",
                    "sensor_yaw_rad",
                    "min_range_m",
                    "finite_count",
                    "sensor_entity",
                    "new_known_cells",
                    "cumulative_known_cells",
                ]
            )

            writer.writerows(
                accepted_records
            )

        # Write the full validity grid separately for diagnostics.
        with (
            output
            / "all_probe_poses.csv"
        ).open(
            "w",
            newline="",
            encoding="utf-8",
        ) as f:
            writer = csv.writer(
                f
            )

            writer.writerow(
                [
                    "requested_x",
                    "requested_y",
                    "actual_x",
                    "actual_y",
                    "drift_m",
                    "finite_count",
                    "min_range_m",
                    "locally_valid",
                    "connected",
                    "sensor_entity",
                ]
            )

            # Reconstruct connected flag by requested coordinate.
            connected_xy = {
                (
                    round(
                        float(
                            coordinates[
                                key[0]
                            ]
                        ),
                        8,
                    ),
                    round(
                        float(
                            coordinates[
                                key[1]
                            ]
                        ),
                        8,
                    ),
                )
                for key in connected
            }

            for row in all_probe_rows:
                requested_xy = (
                    round(
                        float(
                            row[0]
                        ),
                        8,
                    ),
                    round(
                        float(
                            row[1]
                        ),
                        8,
                    ),
                )

                row = list(
                    row
                )

                row[8] = int(
                    requested_xy
                    in connected_xy
                )

                writer.writerow(
                    row
                )

        sensor_entities = sorted(
            {
                record[
                    "sensor_entity"
                ]
                for record in valid_records.values()
                if record[
                    "sensor_entity"
                ]
            }
        )

        summary = {
            "schema_version": 5,
            "evaluator_revision": (
                "v4.1-ever-observed"
            ),
            "definition": (
                "union of LiDAR-observed known cells "
                "from origin-connected collision-valid Gazebo poses"
            ),
            "coverage_metric": (
                "known_area_m2"
            ),
            "occupancy_semantics": (
                "coverage_monitor_v3_1"
            ),
            "coverage_semantics": (
                "ever_observed_lidar_cells"
            ),
            "resolution_m": (
                args.resolution
            ),
            "map_size_m": (
                args.map_size_m
            ),
            "origin_x": (
                origin_x
            ),
            "origin_y": (
                origin_y
            ),
            "probe_min_coordinate_m": (
                args.min_coordinate
            ),
            "probe_max_coordinate_m": (
                args.max_coordinate
            ),
            "probe_step_m": (
                args.step
            ),
            "minimum_clearance_m": (
                args.minimum_clearance
            ),
            "max_ray_range_m": (
                args.max_ray_range_m
            ),
            "occupied_hit_threshold": (
                args.occupied_hit_threshold
            ),
            "tested_poses": (
                total
            ),
            "locally_valid_poses": (
                len(
                    valid_records
                )
            ),
            "connected_accepted_poses": (
                len(
                    connected
                )
            ),
            "disconnected_valid_poses": (
                len(
                    disconnected
                )
            ),
            "connectivity_seed_xy": [
                float(
                    seed_xy[0]
                ),
                float(
                    seed_xy[1]
                ),
            ],
            "sensor_entities": (
                sensor_entities
            ),
            "sensor_pose_source": (
                "gazebo_entity_state"
            ),
            "free_cells": len(
                free_cells
            ),
            "occupied_cells": len(
                occupied_cells
            ),
            "unconfirmed_hit_cells": len(
                occupied_hit_counts.keys()
                - occupied_cells
            ),
            "candidate_observed_cells": len(
                candidate_observed_cells
            ),
            "known_cells": len(
                known_cells
            ),
            "free_area_m2": (
                free_area
            ),
            "occupied_area_m2": (
                occupied_area
            ),
            "reference_known_area_m2": (
                known_area
            ),
            "provisional_95_area_m2": (
                0.95
                * known_area
            ),
            "threshold_95_status": (
                "provisional_not_yet_approved"
            ),
            "clipped_ray_endpoints": (
                clipped_ray_endpoints
            ),
        }

        with (
            output
            / "reference_coverage_summary.json"
        ).open(
            "w",
            encoding="utf-8",
        ) as f:
            json.dump(
                summary,
                f,
                indent=2,
                ensure_ascii=False,
            )

        print()
        print(
            "=================================================="
        )
        print(
            "REFERENCE COVERAGE V4 RESULT"
        )
        print(
            "=================================================="
        )

        print(
            f"tested poses       = "
            f"{total}"
        )

        print(
            f"locally valid      = "
            f"{len(valid_records)}"
        )

        print(
            f"connected accepted = "
            f"{len(connected)}"
        )

        print(
            f"disconnected valid = "
            f"{len(disconnected)}"
        )

        print(
            "sensor entity      = "
            + (
                ", ".join(
                    sensor_entities
                )
                if sensor_entities
                else "NONE"
            )
        )

        print(
            f"free area          = "
            f"{free_area:.3f} m²"
        )

        print(
            f"occupied area      = "
            f"{occupied_area:.3f} m²"
        )

        print(
            f"C_max V4           = "
            f"{known_area:.3f} m²"
        )

        print(
            f"95% provisional    = "
            f"{0.95 * known_area:.3f} m²"
        )

        print(
            f"unconfirmed hits   = "
            f"{len(occupied_hit_counts.keys() - occupied_cells)}"
        )

        print(
            f"clipped endpoints  = "
            f"{clipped_ray_endpoints}"
        )

    finally:
        node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
