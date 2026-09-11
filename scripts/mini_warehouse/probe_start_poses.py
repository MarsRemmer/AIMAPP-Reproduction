#!/usr/bin/env python3

import argparse
import csv
import math
import time
from pathlib import Path

import numpy as np
import rclpy

from gazebo_msgs.msg import EntityState
from gazebo_msgs.srv import GetEntityState, SetEntityState
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import LaserScan


class StartPoseProbe(Node):

    def __init__(self):
        super().__init__("start_pose_probe")

        self.scan = None
        self.scan_revision = 0

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

    def _scan_callback(self, msg):
        self.scan = msg
        self.scan_revision += 1

    def wait_services(self):
        if not self.set_client.wait_for_service(timeout_sec=15.0):
            raise RuntimeError(
                "/gazebo/set_entity_state unavailable"
            )

        if not self.get_client.wait_for_service(timeout_sec=15.0):
            raise RuntimeError(
                "/gazebo/get_entity_state unavailable"
            )

    def call(self, client, request, timeout=5.0):
        future = client.call_async(request)

        deadline = time.monotonic() + timeout

        while rclpy.ok() and not future.done():
            rclpy.spin_once(
                self,
                timeout_sec=0.05,
            )

            if time.monotonic() > deadline:
                raise TimeoutError(
                    "Gazebo service call timed out"
                )

        return future.result()

    def teleport(self, x, y, yaw=0.0, z=0.01):
        request = SetEntityState.Request()

        state = EntityState()
        state.name = "waffle_pi_plus"
        state.reference_frame = "world"

        state.pose.position.x = float(x)
        state.pose.position.y = float(y)
        state.pose.position.z = float(z)

        state.pose.orientation.z = math.sin(yaw / 2.0)
        state.pose.orientation.w = math.cos(yaw / 2.0)

        # Twist remains zero.
        request.state = state

        result = self.call(
            self.set_client,
            request,
        )

        return bool(
            result is not None
            and result.success
        )

    def physical_pose(self):
        request = GetEntityState.Request()

        request.name = "waffle_pi_plus"
        request.reference_frame = "world"

        result = self.call(
            self.get_client,
            request,
        )

        if result is None or not result.success:
            return None

        return (
            float(result.state.pose.position.x),
            float(result.state.pose.position.y),
            float(result.state.pose.position.z),
        )

    def fresh_scan_after(self, previous_revision, timeout=1.5):
        deadline = time.monotonic() + timeout

        while rclpy.ok():
            rclpy.spin_once(
                self,
                timeout_sec=0.05,
            )

            if (
                self.scan is not None
                and self.scan_revision > previous_revision
            ):
                return self.scan

            if time.monotonic() > deadline:
                return None

        return None


def evaluate_scan(scan):

    if scan is None:
        return None

    ranges = np.asarray(
        scan.ranges,
        dtype=float,
    )

    valid = (
        np.isfinite(ranges)
        & (ranges >= float(scan.range_min))
        & (ranges <= float(scan.range_max))
    )

    finite = ranges[valid]

    if len(finite) == 0:
        return {
            "finite_count": 0,
            "finite_fraction": 0.0,
            "min_range": math.inf,
            "median_range": math.inf,
        }

    return {
        "finite_count": int(len(finite)),
        "finite_fraction": float(
            len(finite) / len(ranges)
        ),
        "min_range": float(
            np.min(finite)
        ),
        "median_range": float(
            np.median(finite)
        ),
    }


def farthest_points(candidates, count):

    points = np.asarray(
        [
            [c["x"], c["y"]]
            for c in candidates
        ],
        dtype=float,
    )

    # Start with safe point nearest (0, 0).
    first = int(
        np.argmin(
            np.sum(points ** 2, axis=1)
        )
    )

    selected = [first]

    min_dist_sq = np.sum(
        (points - points[first]) ** 2,
        axis=1,
    )

    while len(selected) < count:

        index = int(
            np.argmax(min_dist_sq)
        )

        if index in selected:
            break

        selected.append(index)

        distance_sq = np.sum(
            (
                points
                - points[index]
            ) ** 2,
            axis=1,
        )

        min_dist_sq = np.minimum(
            min_dist_sq,
            distance_sq,
        )

    return [
        candidates[index]
        for index in selected
    ]


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--output",
        required=True,
    )

    parser.add_argument(
        "--count",
        type=int,
        default=10,
    )

    parser.add_argument(
        "--min-coordinate",
        type=float,
        default=-2.5,
    )

    parser.add_argument(
        "--max-coordinate",
        type=float,
        default=2.5,
    )

    parser.add_argument(
        "--step",
        type=float,
        default=0.5,
    )

    parser.add_argument(
        "--minimum-clearance",
        type=float,
        default=0.55,
    )

    args = parser.parse_args()

    rclpy.init()

    node = StartPoseProbe()

    try:
        node.wait_services()

        # ----------------------------------------------------
        # The verified AIMAPP start at (0, 0) defines the
        # correct settled model height for this Gazebo world.
        # The Mini Warehouse floor is not located at world z=0.
        # ----------------------------------------------------
        print("Calibrating floor height at verified origin (0, 0)...")

        settle_deadline = time.monotonic() + 2.0

        while time.monotonic() < settle_deadline:
            rclpy.spin_once(
                node,
                timeout_sec=0.05,
            )

        reference_pose = node.physical_pose()

        if reference_pose is None:
            raise RuntimeError(
                "unable to read verified origin pose"
            )

        reference_x, reference_y, reference_z = reference_pose

        print(
            "Reference settled pose = "
            f"({reference_x:.3f}, "
            f"{reference_y:.3f}, "
            f"{reference_z:.3f})"
        )

        # In the verified Mini Warehouse runtime the robot must settle
        # near the warehouse floor. A very negative z means the probe
        # world lost its supporting collision geometry and the robot is
        # falling. Abort immediately instead of wasting minutes probing.
        if reference_z < -2.0:
            raise RuntimeError(
                "probe robot is falling through the world: "
                f"reference z={reference_z:.3f}; "
                "world assets/collision geometry are not valid"
            )

        coordinates = np.arange(
            args.min_coordinate,
            args.max_coordinate + args.step / 2.0,
            args.step,
        )

        accepted = []
        tested = 0

        print(
            f"Testing {len(coordinates) ** 2} Gazebo poses..."
        )

        for x in coordinates:
            for y in coordinates:

                tested += 1

                previous_revision = (
                    node.scan_revision
                )

                if not node.teleport(
                    float(x),
                    float(y),
                    0.0,
                    reference_z,
                ):
                    continue

                # Let Gazebo physics settle.
                end = time.monotonic() + 0.30

                while time.monotonic() < end:
                    rclpy.spin_once(
                        node,
                        timeout_sec=0.05,
                    )

                scan = node.fresh_scan_after(
                    previous_revision,
                    timeout=1.0,
                )

                physical = (
                    node.physical_pose()
                )

                metrics = evaluate_scan(
                    scan
                )

                if (
                    physical is None
                    or metrics is None
                ):
                    continue

                px, py, pz = physical

                drift = math.hypot(
                    px - float(x),
                    py - float(y),
                )

                # Conservative test:
                #  - robot did not get pushed out by collision
                #  - robot remains on normal floor height
                #  - LiDAR has real returns
                #  - nearest obstacle is safely outside robot footprint
                # A candidate is rejected if Gazebo collision
                # dynamics move it substantially, if it is not on the
                # same floor level as the verified origin, or if a real
                # LiDAR hit is too close to the robot.
                #
                # A scan containing only +inf is valid: it simply means
                # no obstacle was returned within the sensor range.
                height_error = abs(
                    pz - reference_z
                )

                lidar_clear = (
                    metrics["finite_count"] == 0
                    or metrics["min_range"]
                    >= args.minimum_clearance
                )

                valid_pose = (
                    drift <= 0.12
                    and height_error <= 0.10
                    and lidar_clear
                )

                print(
                    f"probe x={float(x):5.2f} y={float(y):5.2f} | "
                    f"actual=({px:5.2f},{py:5.2f},{pz:5.2f}) | "
                    f"drift={drift:.3f} | "
                    f"dz={height_error:.3f} | "
                    f"finite={metrics['finite_count']} "
                    f"({metrics['finite_fraction']:.3f}) | "
                    f"min={metrics['min_range']:.3f} | "
                    f"median={metrics['median_range']:.3f} | "
                    f"{'ACCEPT' if valid_pose else 'REJECT'}"
                )

                if valid_pose:
                    accepted.append(
                        {
                            "x": float(x),
                            "y": float(y),
                            "yaw_rad": 0.0,
                            "lidar_clearance_m":
                                metrics["min_range"],
                            "finite_fraction":
                                metrics["finite_fraction"],
                            "pose_drift_m":
                                drift,
                        }
                    )

        print()
        print("==================================================")
        print("GAZEBO PROBE SUMMARY")
        print("==================================================")
        print("tested poses    =", tested)
        print("accepted poses  =", len(accepted))

        if len(accepted) < args.count:
            raise RuntimeError(
                f"Only {len(accepted)} safe poses found; "
                f"need {args.count}."
            )

        selected = farthest_points(
            accepted,
            args.count,
        )

        output = Path(
            args.output
        )

        output.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        with output.open(
            "w",
            newline="",
            encoding="utf-8",
        ) as file:

            writer = csv.writer(
                file
            )

            writer.writerow(
                [
                    "candidate",
                    "x",
                    "y",
                    "yaw_rad",
                    "lidar_clearance_m",
                    "finite_fraction",
                    "pose_drift_m",
                ]
            )

            for index, item in enumerate(
                selected,
                start=1,
            ):
                writer.writerow(
                    [
                        index,
                        f'{item["x"]:.3f}',
                        f'{item["y"]:.3f}',
                        f'{item["yaw_rad"]:.3f}',
                        f'{item["lidar_clearance_m"]:.3f}',
                        f'{item["finite_fraction"]:.3f}',
                        f'{item["pose_drift_m"]:.3f}',
                    ]
                )

        print()
        print("SELECTED START POSES")
        print(
            output.read_text(
                encoding="utf-8"
            )
        )

        # Check spatial separation.
        selected_xy = np.asarray(
            [
                [item["x"], item["y"]]
                for item in selected
            ]
        )

        distances = []

        for i in range(len(selected_xy)):
            for j in range(i + 1, len(selected_xy)):
                distances.append(
                    float(
                        np.linalg.norm(
                            selected_xy[i]
                            - selected_xy[j]
                        )
                    )
                )

        if distances:
            print(
                "minimum selected separation =",
                f"{min(distances):.3f} m",
            )
        else:
            print(
                "minimum selected separation = N/A "
                "(only one candidate selected)"
            )

    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
