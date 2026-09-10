# Mini Warehouse Startup Baseline

记录日期：2026-09-10

## Baseline A

启动顺序：`gzserver -> gzclient -> spawn robot`

对应脚本：
- `scripts/mini_warehouse/baseline_A_1_server.sh`
- `scripts/mini_warehouse/baseline_A_2_gui.sh`
- `scripts/mini_warehouse/baseline_A_3_spawn_robot.sh`

实测结果：
- Mini Warehouse 地图可正常加载。
- 修正 Gazebo 模型搜索路径后，原始 AIMAPP `waffle_pi_plus` 可直接正常显示。
- 早期约 3 min 的等待属于环境路径配置异常，不作为正常启动性能结果。

## Baseline B

启动顺序：`gzserver -> spawn robot -> gzclient`

对应脚本：
- `scripts/mini_warehouse/baseline_B_1_server.sh`
- `scripts/mini_warehouse/baseline_B_2_spawn_robot.sh`
- `scripts/mini_warehouse/baseline_B_3_gui.sh`

实测结果：
- Baseline B 与 Baseline A 使用相同的完整 Gazebo 模型搜索路径。
- 早期记录的约 4 min 等待属于同一环境路径配置异常。

## 当前结论

两种启动方式均已验证可以正常工作。

最终确认问题不是 AIMAPP 算法、相机、LiDAR、Gazebo ROS plugin、GPU 或 Mini Warehouse 世界本身。

根因是启动脚本覆盖 `GAZEBO_MODEL_PATH` 时遗漏了 `turtlebot3_gazebo/models`，导致 TurtleBot3 SDF 中的 `model://turtlebot3_common/...` mesh 资源不能立即解析。

补齐 TurtleBot3 模型搜索路径后，标准 `turtlebot3_waffle_pi` 与原始 AIMAPP `waffle_pi_plus` 均可直接正常显示。

因此此前约 3–4 min 的等待记录仅作为环境故障排查记录保留，不再作为 AIMAPP 正常启动性能基线。


## AIMAPP Agent

Mini Warehouse 环境与机器人正常启动后，第四个终端执行：

`scripts/mini_warehouse/baseline_A_4_agent.sh`

该脚本负责：

- 加载 ROS2 Humble 与 `aimapp_reproduction_ws` overlay；
- 确保原作者四个关键 Python 节点具有 executable 权限；
- 从 `~/aimapp_reproduction_ws/src/aimapp` 启动原作者 `agent_launch.py`；
- 使用初始认知位置 `x=0.0, y=0.0`。

2026-09-10 已实测完成至少 20 个 AIMAPP high-level steps，完整自主闭环正常运行。

详细结果见 `docs/PR01_MINI_WAREHOUSE_SMOKE.md`。
