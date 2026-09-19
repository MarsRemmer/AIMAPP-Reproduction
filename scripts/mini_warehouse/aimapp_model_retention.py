#!/usr/bin/env python3

"""
Keep only selected AIMAPP model.pkl snapshots.

Policy:
- Never modify AIMAPP source code.
- Never delete model_temp.pkl.
- Never delete CSV / PNG / panorama / other outputs.
- Keep every N-th step model.pkl.
- Always keep the newest model.pkl for each AIMAPP run.
"""

import argparse
import re
import time
from collections import defaultdict
from pathlib import Path


STEP_PATTERN = re.compile(r"^step_(\d+)\*?$")


def collect_models(tests_root: Path):
    groups = defaultdict(list)

    for path in tests_root.rglob("model.pkl"):
        match = STEP_PATTERN.match(path.parent.name)

        if match is None:
            continue

        step = int(match.group(1))

        # Example:
        # tests/0/step_151/model.pkl
        #
        # Group by the AIMAPP run directory:
        # tests/0
        run_root = path.parent.parent

        stat = path.stat()

        groups[run_root].append(
            {
                "path": path,
                "step": step,
                "mtime_ns": stat.st_mtime_ns,
                "size": stat.st_size,
            }
        )

    return groups


def prune_once(tests_root: Path, keep_every: int):
    groups = collect_models(tests_root)

    total_deleted = 0
    total_freed = 0

    for run_root, models in sorted(groups.items()):
        if not models:
            continue

        newest = max(
            models,
            key=lambda item: (
                item["step"],
                item["mtime_ns"],
            ),
        )

        deleted = []

        for item in models:
            keep_checkpoint = (
                item["step"] % keep_every == 0
            )

            keep_latest = (
                item["path"] == newest["path"]
            )

            if keep_checkpoint or keep_latest:
                continue

            # AIMAPP writes model_temp.pkl first and atomically
            # renames it to model.pkl afterwards. We only remove
            # completed historical model.pkl files.
            item["path"].unlink()

            deleted.append(item)

            total_deleted += 1
            total_freed += item["size"]

        if deleted:
            print(
                f"[retention] run={run_root} "
                f"deleted={len(deleted)} "
                f"freed_mib="
                f"{sum(x['size'] for x in deleted) / 1024 / 1024:.2f} "
                f"latest={newest['path'].parent.name}",
                flush=True,
            )

    return total_deleted, total_freed


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "tests_root",
        type=Path,
        help="AIMAPP native tests directory",
    )

    parser.add_argument(
        "--keep-every",
        type=int,
        default=50,
    )

    parser.add_argument(
        "--watch",
        action="store_true",
        help="Run continuously instead of once",
    )

    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
    )

    args = parser.parse_args()

    if args.keep_every <= 0:
        raise SystemExit(
            "--keep-every must be positive"
        )

    if args.interval <= 0:
        raise SystemExit(
            "--interval must be positive"
        )

    args.tests_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    if not args.watch:
        deleted, freed = prune_once(
            args.tests_root,
            args.keep_every,
        )

        print(
            f"[retention] complete "
            f"deleted={deleted} "
            f"freed_mib={freed / 1024 / 1024:.2f}"
        )

        return

    print(
        "[retention] watching "
        f"{args.tests_root} "
        f"keep_every={args.keep_every} "
        f"interval={args.interval}s",
        flush=True,
    )

    try:
        while True:
            prune_once(
                args.tests_root,
                args.keep_every,
            )

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print(
            "[retention] stopped",
            flush=True,
        )


if __name__ == "__main__":
    main()
