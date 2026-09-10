# PR-01 Mini Warehouse AIMAPP Smoke Test

记录日期：2026-09-10

## 实验目的

验证原作者 AIMAPP 公开代码能否在 Mini Warehouse 中完成连续自主导航闭环。

## 代码基线

AIMAPP 原作者固定 commit：

`213a4dc856b06819964511bdcd94e57db62e0913`

实验工作空间：

`~/aimapp_reproduction_ws`

## 环境兼容处理

本阶段仅进行了两项运行环境兼容处理，未修改 AIMAPP 算法逻辑：

1. 修正 `GAZEBO_MODEL_PATH`，补充 `turtlebot3_gazebo/models`，解决 `waffle_pi_plus` mesh 资源解析等待问题。
2. 为 `main.py`、panorama、potential field 和 odometry alignment 四个 Python 节点增加 executable 权限，使 ROS2 能正确识别并启动节点。

## 正式启动

Baseline A 固定为四步：

1. `baseline_A_1_server.sh`
2. `baseline_A_2_gui.sh`
3. `baseline_A_3_spawn_robot.sh`
4. `baseline_A_4_agent.sh`

## 实验结果

AIMAPP 四个核心节点均正常启动，并成功完成全景观测、状态推断、主动推断/MCTS 决策、Potential Field 运动执行、再观测、模型更新和重新规划。

本次运行至少持续至 `step 20`，观测状态持续扩展；期间多次出现运动受阻，并成功触发 stuck detection、goal abort、返回上一认知位置和重新规划机制。

## 结论

PR-01：PASS。

当前结论仅代表原作者公开代码级 AIMAPP Mini Warehouse 单次完整闭环运行成功，尚不代表论文 CE、nAUC、Success Rate 等定量结果已经复现。

下一阶段首先审计论文正式实验协议，包括 Potential Field / Nav2、实验终止条件、CE 与 nAUC 的具体计算方式以及正式运行次数。
