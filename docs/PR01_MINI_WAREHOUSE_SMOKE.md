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

## Nav2 对照验证

在原始 Potential Field 版本完成闭环运行后，进一步对运动执行层进行了 Nav2 对照验证。为避免修改 AIMAPP 高层算法，仅将 `main.py` 中的运动客户端由 `PFClient()` 切换为 `Nav2Client()`，AIMAPP 的状态推断、认知地图、EFE、MCTS 及目标选择逻辑均保持不变。

验证过程中发现，当前 Mini Warehouse 的独立 Gazebo spawn 流程未启动 `robot_state_publisher`，导致 TF 树缺少 `base_footprint -> base_link`，Nav2 的 `controller_server` 因无法建立 `odom -> base_link` 变换而停留在配置阶段。使用 TurtleBot3 Waffle Pi 的 URDF 经 xacro 正确展开后启动 `robot_state_publisher`，TF 链恢复完整，Nav2 的 controller、planner、behavior、bt_navigator 和 waypoint_follower 均成功进入 active 状态。

随后 AIMAPP 在 Nav2 运动层下成功开始自主运行。单次定性观察显示，相比原始 Potential Field，机器人在 Mini Warehouse 中的墙边、转角和障碍附近运动更稳定、局部处理更顺畅。该结果目前仅作为运动层诊断证据，不作为定量性能结论。

由此进一步明确：此前观察到的墙边磨蹭、局部旋转和运动受阻，至少有相当一部分来源于原始 Potential Field 运动执行层，不能直接归因于 AIMAPP 的主动推断高层决策。

## 后续系统架构决定

后续 SCA-AIFNav 统一采用以下分层架构：

- SCA-AIFNav：负责状态推断、认知地图、结构复杂度建模、EFE、MCTS 和高层策略选择，即解决“为什么去、下一步去哪里”；
- Nav2：负责路径规划、局部避障、轨迹跟踪和运动控制，即解决“确定目标后如何安全到达”。

Potential Field 后续仅保留为 AIMAPP 原始公开代码的复现基线，不再作为 SCA-AIFNav 的默认运动执行层。

同时，主动推断“多目标决策”的研究定位保持不变：期望自由能在高层策略选择层面统一协调目标导向价值与信息价值，减少对多个独立奖励/损失函数及人工权重组合的依赖；Nav2 所处理的底层路径规划与运动控制不属于这一层面的多目标策略选择问题。

## 下一步

1. 将当前 Nav2 + Mini Warehouse 的启动流程整理为稳定、可重复的脚本，补齐 `robot_state_publisher` 等必要环节；
2. 在固定环境下进行 AIMAPP 重复运行与定量复现；
3. 继续审计论文实验协议及结果后处理代码，包括 CE、nAUC、coverage-distance 等指标实现；
4. 在 AIMAPP 复现基线稳定后继续 SCA-AIFNav 的结构复杂度自适应改进。
