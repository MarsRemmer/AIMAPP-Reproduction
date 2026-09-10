# AIMAPP-Reproduction

AIMAPP 论文结果复现与实验记录仓库。

本仓库用于固定 AIMAPP 论文复现过程中已经验证的环境、启动脚本和实验记录。

## Mini Warehouse 启动基线

### Baseline A

启动顺序：`gzserver -> gzclient -> spawn robot`

三个终端依次执行：

```bash
bash scripts/mini_warehouse/baseline_A_1_server.sh
bash scripts/mini_warehouse/baseline_A_2_gui.sh
bash scripts/mini_warehouse/baseline_A_3_spawn_robot.sh
```

实测：spawn_entity 约 1.02 s 返回成功；Gazebo Real Time 约 3 min 20 s 时小车最终出现。

### Baseline B

启动顺序：`gzserver -> spawn robot -> gzclient`

三个终端依次执行：

```bash
bash scripts/mini_warehouse/baseline_B_1_server.sh
bash scripts/mini_warehouse/baseline_B_2_spawn_robot.sh
bash scripts/mini_warehouse/baseline_B_3_gui.sh
```

实测：无 GUI Spawn 约 0.77 s；Gazebo Real Time 约 4 min 16 s 时地图和小车最终一起出现。

两种方法均已验证可以正常启动，但 AIMAPP 机器人加入后存在明显的 Gazebo 初始化/渲染卡顿。

详细记录见 `docs/MINI_WAREHOUSE_STARTUP_BASELINE.md`。
