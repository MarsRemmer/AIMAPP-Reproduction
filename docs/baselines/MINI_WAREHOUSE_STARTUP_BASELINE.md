# Mini Warehouse Startup Baseline

记录日期：2026-09-10

## 当前唯一正式基线

Mini Warehouse 后续统一采用 **Baseline A v2（Nav2）**。
旧 Baseline B 已删除，不再使用。

运行工作区：`~/SCA-AIFNav-Project/aimapp/runtime_ws`
原作者只读审计副本：`~/SCA-AIFNav-Project/aimapp/audit/aimapp_ref`

## 固定启动顺序

1. `baseline_A_1_server.sh`：启动 Gazebo Server
2. `baseline_A_2_gui.sh`：启动 Gazebo GUI
3. `baseline_A_3_spawn_robot.sh`：生成 waffle_pi_plus，并启动 robot_state_publisher
4. `baseline_A_4_nav2.sh`：启动 Nav2
5. `baseline_A_5_agent.sh`：启动 AIMAPP Agent

统一执行位置：

`~/SCA-AIFNav-Project/aimapp/reproduction/scripts/mini_warehouse/`

## 关键环境修正

A1/A2 已补齐 `turtlebot3_gazebo/models` 到 `GAZEBO_MODEL_PATH`，解决此前 Mini Warehouse 中 TurtleBot3 mesh 资源解析造成的数分钟启动等待。

A3 在 spawn 机器人后，通过 xacro 展开 TurtleBot3 Waffle Pi URDF 并启动 `robot_state_publisher`，补齐：

`odom -> base_footprint -> base_link`

从而满足 Nav2 对 TF 的要求。

A5 自动检查 Python 节点 executable 权限，并要求当前 AIMAPP 使用：

`self.motion_client = Nav2Client()`

## 当前架构决定

AIMAPP / SCA-AIFNav 负责状态推断、认知地图、EFE、MCTS 和高层策略选择，即“为什么去、下一步去哪里”。

Nav2 负责路径规划、局部避障、轨迹跟踪和运动控制，即“目标确定后如何安全到达”。

Potential Field 仅保留为原作者公开代码的复现基线，不再作为后续 SCA-AIFNav 默认运动层。

详细闭环验证见：

`docs/PR01_MINI_WAREHOUSE_SMOKE.md`
