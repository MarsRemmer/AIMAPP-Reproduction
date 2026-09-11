# Experiment Results

This directory is no longer used for new experiment output.

All project-level experiment data is stored under:

`~/SCA-AIFNav-Project/experiments/`

Current convention:

- `experiments/mini_warehouse/smoke/`
  - integration checks and recorder preflight runs

- `experiments/mini_warehouse/formal/aimapp_nav2/`
  - formal AIMAPP + Nav2 baseline runs

- `experiments/mini_warehouse/formal/sca_baseline_nav2/`
  - formal SCA-AIFNav baseline + Nav2 runs

- `experiments/mini_warehouse/processed/`
  - processed tables and cross-run statistics

- `experiments/mini_warehouse/figures/`
  - final comparison figures

- `experiments/archive/`
  - historical runs retained for provenance

Historical raw AIMAPP datasets formerly stored in `results/raw/`
were migrated to the project-level `experiments/archive/` directory
on 2026-09-11 and verified using SHA256 manifests.

Do not place new raw or formal experiment data in this repository.
