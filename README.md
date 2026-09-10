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

修正 Gazebo 模型搜索路径后，原始 AIMAPP waffle_pi_plus 可直接正常显示。

### Baseline B

启动顺序：`gzserver -> spawn robot -> gzclient`

三个终端依次执行：

```bash
bash scripts/mini_warehouse/baseline_B_1_server.sh
bash scripts/mini_warehouse/baseline_B_2_spawn_robot.sh
bash scripts/mini_warehouse/baseline_B_3_gui.sh
```

Baseline B 使用与 Baseline A 相同的完整 Gazebo 模型搜索路径。

两种启动方式均已验证。

早期约 3–4 min 的异常等待已定位为 Gazebo 模型搜索路径不完整：
启动脚本遗漏了 `turtlebot3_gazebo/models`，导致
`model://turtlebot3_common/...` mesh 资源不能立即解析。

补齐该路径后，标准 TurtleBot3 与原始 AIMAPP waffle_pi_plus 均可直接显示。
此前的 3 min 20 s / 4 min 16 s 记录不再作为正常启动性能基线。

详细记录见 `docs/MINI_WAREHOUSE_STARTUP_BASELINE.md`。
