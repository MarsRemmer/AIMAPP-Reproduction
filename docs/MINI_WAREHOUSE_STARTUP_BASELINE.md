# Mini Warehouse Startup Baseline

记录日期：2026-09-10

## Baseline A

启动顺序：`gzserver -> gzclient -> spawn robot`

对应脚本：
- `scripts/mini_warehouse/baseline_A_1_server.sh`
- `scripts/mini_warehouse/baseline_A_2_gui.sh`
- `scripts/mini_warehouse/baseline_A_3_spawn_robot.sh`

实测结果：
- Mini Warehouse 地图加载较快。
- spawn_entity 约 1.02 s 返回成功。
- 机器人加入后 Gazebo GUI 会长时间卡顿。
- Gazebo Real Time 约 3 min 20 s 时小车最终正常显示。

## Baseline B

启动顺序：`gzserver -> spawn robot -> gzclient`

对应脚本：
- `scripts/mini_warehouse/baseline_B_1_server.sh`
- `scripts/mini_warehouse/baseline_B_2_spawn_robot.sh`
- `scripts/mini_warehouse/baseline_B_3_gui.sh`

实测结果：
- 无 GUI 状态下 spawn_entity 约 0.77 s 返回成功。
- 随后启动 gzclient，会长时间停留在 Preparing your world。
- Gazebo Real Time 约 4 min 16 s 时地图和小车最终一起显示。

## 当前结论

两种启动方式均已验证可以正常工作。

当前问题不是世界文件无法加载，也不是 spawn_entity 服务失败，而是 AIMAPP 机器人加入后 Gazebo 存在明显的初始化/渲染卡顿。

已确认 NVIDIA RTX 4060 正常参与 Gazebo/OpenGL 硬件渲染。

后续所有性能排查均以这两套启动方式为基线，并坚持一次只修改一个变量。
