# Experiment Results

## raw/

`raw/` stores complete local AIMAPP runtime snapshots and is intentionally excluded from Git because the generated models and per-step artifacts can be very large.

Current local snapshot:

- `2026-09-10_aimapp_runtime_snapshot/`
- Contains runs `0/` and `1/`.
- Complete snapshot size: approximately 2.7 GB.
- Includes `steps_data.csv`, model snapshots, observations, likelihood plots and other per-step runtime artifacts.
- Runs `0` and `1` are not yet assigned PF/Nav2 labels because their correspondence has not been independently verified.

Processed quantitative results intended for version control should later be placed in `results/processed/`.

## Preserved pre-consolidation run

`raw/2026-09-11_archive_old_ws_run0/`

This directory preserves an independent AIMAPP run recovered from the former
`aimapp_reproduction_ws_old/src/aimapp/tests/0` workspace before deletion of
that legacy workspace.

It is not the same run as
`2026-09-10_aimapp_runtime_snapshot/0`: file counts, step directories and
model/output contents differ. The run is therefore retained separately rather
than merged or overwritten.

As with other raw experiment data, this directory is intentionally excluded
from Git because of its large size.
