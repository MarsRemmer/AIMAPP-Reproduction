#!/usr/bin/env python3
"""Visualize independent exploration coverage as disappearing fog."""

import argparse
import json
import math
import signal
import time
from pathlib import Path

import cv2
import numpy as np
import rclpy

from nav_msgs.msg import OccupancyGrid, Odometry
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from std_msgs.msg import String


class CoverageVisualizer(Node):
    """Render the experiment coverage map without affecting navigation."""

    def __init__(
        self,
        output_dir,
        display=False,
        frame_period_sec=1.0,
        video_fps=8.0,
        image_scale=2,
    ):
        super().__init__(
            "experiment_coverage_visualizer"
        )

        self.output_dir = Path(
            output_dir
        )

        self.frame_dir = (
            self.output_dir
            / "frames"
        )

        self.frame_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        self.display = bool(
            display
        )

        self.frame_period_sec = float(
            frame_period_sec
        )

        self.video_fps = float(
            video_fps
        )

        self.image_scale = max(
            1,
            int(image_scale),
        )

        self.map_message = None
        self.robot_xy = None
        self.stats = {}

        self.trajectory = []

        self.last_trajectory_xy = None

        self.frame_index = 0
        self.last_frame_wall = 0.0
        self.last_saved_known_cells = None

        self.start_wall = (
            time.monotonic()
        )

        self.create_subscription(
            OccupancyGrid,
            "/experiment/coverage_map",
            self._map_callback,
            10,
        )

        self.create_subscription(
            Odometry,
            "/odom",
            self._odom_callback,
            qos_profile_sensor_data,
        )

        self.create_subscription(
            String,
            "/experiment/coverage_stats",
            self._stats_callback,
            10,
        )

        self.create_timer(
            0.2,
            self._render_timer_callback,
        )

        self.get_logger().info(
            "Coverage visualizer started"
        )

    def _map_callback(
        self,
        message,
    ):
        self.map_message = message

    def _odom_callback(
        self,
        message,
    ):
        x = float(
            message.pose.pose.position.x
        )

        y = float(
            message.pose.pose.position.y
        )

        self.robot_xy = (
            x,
            y,
        )

        if self.last_trajectory_xy is None:
            self.trajectory.append(
                (
                    x,
                    y,
                )
            )

            self.last_trajectory_xy = (
                x,
                y,
            )

            return

        px, py = (
            self.last_trajectory_xy
        )

        if (
            math.hypot(
                x - px,
                y - py,
            )
            >= 0.02
        ):
            self.trajectory.append(
                (
                    x,
                    y,
                )
            )

            self.last_trajectory_xy = (
                x,
                y,
            )

    def _stats_callback(
        self,
        message,
    ):
        try:
            self.stats = json.loads(
                message.data
            )
        except Exception:
            pass

    def _world_to_display_pixel(
        self,
        x,
        y,
    ):
        message = self.map_message

        if message is None:
            return None

        resolution = float(
            message.info.resolution
        )

        origin_x = float(
            message.info.origin.position.x
        )

        origin_y = float(
            message.info.origin.position.y
        )

        width = int(
            message.info.width
        )

        height = int(
            message.info.height
        )

        gx = int(
            math.floor(
                (x - origin_x)
                / resolution
            )
        )

        gy = int(
            math.floor(
                (y - origin_y)
                / resolution
            )
        )

        if not (
            0 <= gx < width
            and 0 <= gy < height
        ):
            return None

        return (
            gx,
            height - 1 - gy,
        )

    def _base_image(
        self,
    ):
        message = self.map_message

        if message is None:
            return None

        width = int(
            message.info.width
        )

        height = int(
            message.info.height
        )

        grid = np.asarray(
            message.data,
            dtype=np.int16,
        ).reshape(
            (
                height,
                width,
            )
        )

        # ROS occupancy grid's row 0 corresponds to the
        # lower side of the map. Flip vertically for display.
        grid = np.flipud(
            grid
        )

        image = np.zeros(
            (
                height,
                width,
                3,
            ),
            dtype=np.uint8,
        )

        # Unknown / fog.
        image[
            grid == -1
        ] = (
            135,
            135,
            135,
        )

        # Observed free space.
        image[
            grid == 0
        ] = (
            255,
            255,
            255,
        )

        # Observed obstacle.
        image[
            grid > 0
        ] = (
            0,
            0,
            0,
        )

        return image

    def render(
        self,
    ):
        image = (
            self._base_image()
        )

        if image is None:
            return None

        # Draw travelled trajectory.
        previous = None

        for point in self.trajectory:
            pixel = (
                self._world_to_display_pixel(
                    point[0],
                    point[1],
                )
            )

            if pixel is None:
                continue

            if previous is not None:
                cv2.line(
                    image,
                    previous,
                    pixel,
                    (
                        255,
                        120,
                        0,
                    ),
                    thickness=2,
                    lineType=cv2.LINE_AA,
                )

            previous = pixel

        # Draw current robot position.
        if self.robot_xy is not None:
            pixel = (
                self._world_to_display_pixel(
                    self.robot_xy[0],
                    self.robot_xy[1],
                )
            )

            if pixel is not None:
                cv2.circle(
                    image,
                    pixel,
                    5,
                    (
                        0,
                        0,
                        255,
                    ),
                    thickness=-1,
                    lineType=cv2.LINE_AA,
                )

                cv2.circle(
                    image,
                    pixel,
                    8,
                    (
                        0,
                        0,
                        255,
                    ),
                    thickness=1,
                    lineType=cv2.LINE_AA,
                )

        if self.image_scale != 1:
            image = cv2.resize(
                image,
                None,
                fx=self.image_scale,
                fy=self.image_scale,
                interpolation=(
                    cv2.INTER_NEAREST
                ),
            )

        # Information bar.
        bar_height = 88

        canvas = cv2.copyMakeBorder(
            image,
            bar_height,
            0,
            0,
            0,
            cv2.BORDER_CONSTANT,
            value=(
                235,
                235,
                235,
            ),
        )

        known_area = self.stats.get(
            "known_area_m2"
        )

        distance = self.stats.get(
            "distance_m"
        )

        new_area = self.stats.get(
            "new_known_area_m2"
        )

        elapsed = (
            time.monotonic()
            - self.start_wall
        )

        line1 = (
            "Exploration coverage / fog map"
        )

        line2 = (
            f"Elapsed: {elapsed:6.1f} s"
        )

        if known_area is not None:
            line2 += (
                f"    Known area: "
                f"{float(known_area):.3f} m^2"
            )

        if distance is not None:
            line2 += (
                f"    Distance: "
                f"{float(distance):.3f} m"
            )

        line3 = (
            "Gray=unknown   White=free   "
            "Black=obstacle   Blue=trajectory   Red=robot"
        )

        if new_area is not None:
            line3 += (
                f"    New: "
                f"{float(new_area):.4f} m^2"
            )

        cv2.putText(
            canvas,
            line1,
            (
                12,
                25,
            ),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (
                0,
                0,
                0,
            ),
            2,
            cv2.LINE_AA,
        )

        cv2.putText(
            canvas,
            line2,
            (
                12,
                51,
            ),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (
                0,
                0,
                0,
            ),
            1,
            cv2.LINE_AA,
        )

        cv2.putText(
            canvas,
            line3,
            (
                12,
                75,
            ),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.42,
            (
                0,
                0,
                0,
            ),
            1,
            cv2.LINE_AA,
        )

        return canvas

    def _known_cell_count(
        self,
    ):
        message = self.map_message

        if message is None:
            return None

        data = np.asarray(
            message.data,
            dtype=np.int16,
        )

        return int(
            np.count_nonzero(
                data != -1
            )
        )

    def _render_timer_callback(
        self,
    ):
        image = self.render()

        if image is None:
            return

        if self.display:
            cv2.imshow(
                "Coverage Exploration",
                image,
            )

            key = cv2.waitKey(
                1
            ) & 0xFF

            # q only closes the viewer.
            # It does NOT control AIMAPP/SCA.
            if key == ord("q"):
                self.display = False
                cv2.destroyAllWindows()

        now = time.monotonic()

        if (
            now - self.last_frame_wall
            < self.frame_period_sec
        ):
            return

        known_cells = (
            self._known_cell_count()
        )

        if known_cells is None:
            return

        # Save a frame only when the revealed
        # part of the environment has changed.
        if (
            self.last_saved_known_cells
            == known_cells
        ):
            return

        self.frame_index += 1

        path = (
            self.frame_dir
            / (
                f"frame_"
                f"{self.frame_index:06d}.png"
            )
        )

        cv2.imwrite(
            str(path),
            image,
        )

        # Keep a continuously updated still image too.
        cv2.imwrite(
            str(
                self.output_dir
                / "coverage_live.png"
            ),
            image,
        )

        self.last_saved_known_cells = (
            known_cells
        )

        self.last_frame_wall = (
            now
        )

    def _make_video(
        self,
    ):
        paths = sorted(
            self.frame_dir.glob(
                "frame_*.png"
            )
        )

        if len(paths) < 2:
            return None

        first = cv2.imread(
            str(paths[0])
        )

        if first is None:
            return None

        height, width = (
            first.shape[:2]
        )

        mp4_path = (
            self.output_dir
            / "coverage_exploration.mp4"
        )

        writer = cv2.VideoWriter(
            str(mp4_path),
            cv2.VideoWriter_fourcc(
                *"mp4v"
            ),
            self.video_fps,
            (
                width,
                height,
            ),
        )

        final_path = mp4_path

        if not writer.isOpened():
            avi_path = (
                self.output_dir
                / "coverage_exploration.avi"
            )

            writer = cv2.VideoWriter(
                str(avi_path),
                cv2.VideoWriter_fourcc(
                    *"MJPG"
                ),
                self.video_fps,
                (
                    width,
                    height,
                ),
            )

            final_path = avi_path

        if not writer.isOpened():
            return None

        for path in paths:
            frame = cv2.imread(
                str(path)
            )

            if frame is None:
                continue

            if (
                frame.shape[1] != width
                or frame.shape[0] != height
            ):
                frame = cv2.resize(
                    frame,
                    (
                        width,
                        height,
                    ),
                )

            writer.write(
                frame
            )

        # Pause on the final explored map.
        final_frame = cv2.imread(
            str(paths[-1])
        )

        if final_frame is not None:
            for _ in range(
                int(
                    self.video_fps
                    * 2.0
                )
            ):
                writer.write(
                    final_frame
                )

        writer.release()

        return final_path

    def close(
        self,
    ):
        image = self.render()

        if image is not None:
            cv2.imwrite(
                str(
                    self.output_dir
                    / "coverage_final.png"
                ),
                image,
            )

        video_path = (
            self._make_video()
        )

        summary = {
            "frames_saved": (
                self.frame_index
            ),
            "trajectory_points": len(
                self.trajectory
            ),
            "video": (
                str(video_path)
                if video_path
                else None
            ),
            "display_enabled": (
                self.display
            ),
        }

        with (
            self.output_dir
            / "visualization_summary.json"
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

        print(
            "Coverage visualization finished:"
        )

        print(
            f"  frames = "
            f"{self.frame_index}"
        )

        print(
            f"  video  = "
            f"{video_path}"
        )

        cv2.destroyAllWindows()


def parse_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    parser.add_argument(
        "--display",
        action="store_true",
    )

    parser.add_argument(
        "--frame-period-sec",
        type=float,
        default=1.0,
    )

    parser.add_argument(
        "--video-fps",
        type=float,
        default=8.0,
    )

    parser.add_argument(
        "--image-scale",
        type=int,
        default=2,
    )

    return parser.parse_known_args()


def main():
    args, ros_args = (
        parse_arguments()
    )

    rclpy.init(
        args=ros_args
    )

    def _graceful_sigterm(
        signum,
        frame,
    ):
        raise KeyboardInterrupt

    signal.signal(
        signal.SIGTERM,
        _graceful_sigterm,
    )

    node = CoverageVisualizer(
        output_dir=(
            args.output_dir
        ),
        display=(
            args.display
        ),
        frame_period_sec=(
            args.frame_period_sec
        ),
        video_fps=(
            args.video_fps
        ),
        image_scale=(
            args.image_scale
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
