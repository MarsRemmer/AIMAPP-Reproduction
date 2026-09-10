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
