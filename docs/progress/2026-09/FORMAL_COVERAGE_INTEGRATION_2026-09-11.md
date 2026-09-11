# Formal Runner Coverage Monitor 集成记录

**日期：2026年9月11日**

正式 Mini Warehouse paired experiment 在每个 run 中自动启动同一套外部
ever-observed Coverage Monitor。

固定评价协议：

```text
coverage semantics : ever_observed_lidar_cells
resolution         : 0.05 m
canvas             : 40.0 m × 40.0 m
max LiDAR range    : 12.0 m
```

Coverage Monitor 不向 AIMAPP 或 SCA-AIFNav 反馈任何信息，只承担外部评价。

每个正式 run 必须保存：

```text
coverage/
├── coverage.csv
├── coverage_metadata.json
├── coverage_summary.json
├── coverage_grid.npz
└── coverage_map.png
```

ROS bag 同时新增原始 `/scan`，因此后续可以独立重算 coverage。

formal runner 在 monitor 中途退出时记录
`reason=coverage_monitor_exited`；若算法完成但 coverage 输出不完整，则记录
`reason=coverage_output_incomplete`。失败 trial 保留，但不计入完整成功配对。

算法停止条件仍固定为 200 个完成的高层动作；coverage 不参与提前停止。
