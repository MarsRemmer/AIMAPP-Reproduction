# AIMAPP-Reproduction

AIMAPP 论文代码复现、实验验证与问题审计记录仓库。

本仓库用于保存 AIMAPP 复现过程中已经验证的环境配置、稳定启动脚本、每日工作记录以及代码与实验审计结果。

## 当前代码基线

AIMAPP 官方固定 commit：

`213a4dc856b06819964511bdcd94e57db62e0913`

实际运行工作区：

`~/aimapp_ws`

原作者只读审计副本：

`~/aimapp_reproduction_audit/aimapp_ref`

复现记录仓库：

`~/AIMAPP-Reproduction`

## Mini Warehouse 当前启动基线

当前统一采用：

**Baseline A v2（Nav2）**

启动顺序：

`Gazebo Server`

→ `Gazebo GUI`

→ `Spawn Robot + robot_state_publisher`

→ `Nav2`

→ `AIMAPP Agent`

对应脚本：

`scripts/mini_warehouse/baseline_A_1_server.sh`

`scripts/mini_warehouse/baseline_A_2_gui.sh`

`scripts/mini_warehouse/baseline_A_3_spawn_robot.sh`

`scripts/mini_warehouse/baseline_A_4_nav2.sh`

`scripts/mini_warehouse/baseline_A_5_agent.sh`

详细启动说明：

`docs/baselines/MINI_WAREHOUSE_STARTUP_BASELINE.md`

## 每日工作记录

完整工作过程持续记录于：

`docs/logs/WORK_LOG.md`

该文件按日期记录实际完成的工作、问题排查、代码与配置变化、验证结果以及已经形成的阶段性结论。

## 当前系统架构

后续 SCA-AIFNav 采用：

**SCA-AIFNav + Nav2**

分层架构。

SCA-AIFNav 负责状态推断、认知地图、结构复杂度、Expected Free Energy、MCTS 与高层策略选择。

Nav2 负责目标确定后的路径规划、局部避障、轨迹跟踪与运动控制。

原作者 Potential Field 保留作为 AIMAPP 公开代码运动层复现基线。
