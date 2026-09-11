# AIMAPP Reproduction Work Log

AIMAPP 论文代码复现、运行验证、问题排查与代码审计的持续工作记录。

本文件按日期更新，主要记录实际完成的工作、遇到的问题、排查过程、修改内容、验证结果以及已经形成的阶段性结论。

## 记录原则

工作日志以 AIMAPP 复现与 SCA-AIFNav 主线为核心。

对于日常讨论中与主线关系较弱的问题，不机械记录全部问答过程。只有当相关讨论对以下内容产生实际影响时才写入工作日志：

- 代码实现或配置发生变化；
- 实验设计或复现方法发生变化；
- 对问题根因形成新的判断；
- 系统架构或技术路线发生调整；
- 对论文、算法或实验结果形成需要长期保留的认识。

记录时重点保留“做了什么、为什么做、发现什么、最后得到什么结论”，避免把工作日志写成完整聊天记录。

---

# 2026-09-10

## 1. 今日工作概述

今日主要围绕 AIMAPP 原作者公开代码的 Mini Warehouse 复现环境继续开展运行验证和问题排查。

在此前能够启动 Mini Warehouse 和 AIMAPP 的基础上，重点完成了以下工作：

- 固定 AIMAPP 官方代码版本与运行目录；
- 进一步整理 Mini Warehouse Gazebo 启动异常；
- 验证原作者 Potential Field 版本能够形成完整自主导航闭环；
- 分析 Potential Field 在墙边、转角等位置表现不佳的问题；
- 将 AIMAPP 底层运动执行由 Potential Field 切换为 Nav2；
- 排查并解决 Nav2 所需机器人 TF 缺失问题；
- 排查 AIMAPP Agent 工作目录和 Python executable 权限问题；
- 成功运行 AIMAPP + Nav2；
- 对 Potential Field 与 Nav2 的运动表现进行了初步定性对照；
- 进一步明确 AIMAPP 高层决策与 Nav2 底层路径规划之间的职责；
- 确定后续 SCA-AIFNav 默认采用 Nav2 作为运动执行层；
- 将 Mini Warehouse 启动方式重新整理为唯一 A1～A5 基线；
- 对 AIMAPP 结果后处理 notebook 开始进行初步代码审计。

---

## 2. AIMAPP 官方代码基线重新固定

为避免后续复现过程中由于代码版本变化造成结果不一致，当前原作者 AIMAPP 代码统一固定至：

`213a4dc856b06819964511bdcd94e57db62e0913`

同时将代码用途分成三个独立目录。

### 原作者只读审计副本

路径：

`~/aimapp_reproduction_audit/aimapp_ref`

该目录保持官方代码原始状态，不进行实验性修改，主要用于：

- 与运行版本进行代码对比；
- 后续逐模块代码审计；
- 判断某个问题属于原作者实现还是复现环境修改。

### AIMAPP 实际运行工作区

路径：

`~/aimapp_ws`

AIMAPP 源码位于：

`~/aimapp_ws/src/aimapp`

当前运行分支：

`reproduction`

该目录用于 ROS2 实际编译、运行以及必要的复现兼容调整。

已经在 ROS2 Humble 环境中执行：

`colcon build --symlink-install`

并成功完成：

- `aimapp_actions`
- `aimapp`

两个 package 的构建。

### 复现记录仓库

路径：

`~/AIMAPP-Reproduction`

该目录不承担 AIMAPP 核心代码开发，主要保存：

- 稳定启动脚本；
- 环境问题记录；
- 实验运行记录；
- 复现结论；
- 代码审计结果。

---

## 3. Mini Warehouse Gazebo 长时间加载问题

此前 Mini Warehouse 启动过程中曾出现约数分钟的 Gazebo 等待，机器人模型无法立即正常显示。

排查过程中曾分别考虑：

- Gazebo Server；
- Gazebo GUI；
- Mini Warehouse world；
- TurtleBot3 模型；
- AIMAPP 自定义 `waffle_pi_plus`；
- 相机；
- LiDAR；
- Gazebo ROS plugin；
- 图形渲染。

随后将 Gazebo 启动拆分为：

`gzserver`

→ `gzclient`

→ `spawn robot`

分别验证。

最终确认问题并不来自 AIMAPP 算法，也不是 Mini Warehouse 正常需要较长时间初始化。

实际根因为启动脚本重新设置：

`GAZEBO_MODEL_PATH`

时遗漏：

`turtlebot3_gazebo/models`

导致 `waffle_pi_plus` SDF 中引用的：

`model://turtlebot3_common/...`

相关 mesh 资源无法立即被 Gazebo 找到。

补齐 TurtleBot3 model 路径以后：

- Mini Warehouse 可以正常加载；
- AIMAPP `waffle_pi_plus` 可以正常显示；
- 此前约 3～4 min 的异常等待消失。

因此此前记录的长时间加载被确定为环境路径配置问题，不再作为 AIMAPP 正常启动时间。

---

## 4. 原始 Potential Field AIMAPP 闭环验证

首先保持原作者公开代码默认运动层：

`self.motion_client = PFClient()`

运行 Mini Warehouse。

实际运行中已经观察到完整的 AIMAPP 自主导航闭环：

全景观测

→ 状态推断

→ 认知状态更新

→ Active Inference / MCTS 策略选择

→ 下一目标生成

→ Potential Field 运动执行

→ 新位置观测

→ 模型更新

→ 再次规划

本次运行至少连续执行到约：

`step 20`

说明当前官方 AIMAPP 代码能够在 ROS2 Humble + Gazebo Classic + Mini Warehouse 环境下形成持续自主导航闭环。

因此原 PR-01 的核心结论仍然成立：

**Mini Warehouse 单次完整闭环运行：PASS。**

这里的 PASS 只说明代码和导航闭环能够运行，并不表示论文中的 CE、nAUC、Success Rate 等定量结果已经完成复现。

---

## 5. Potential Field 运动行为观察

在 Potential Field 版本运行过程中，观察到比较明显的局部运动问题：

- 靠近墙体后处理较慢；
- 墙角附近存在反复旋转；
- 部分目标执行时间较长；
- 某些位置出现运动失败；
- stuck detection 被触发；
- 当前 goal 被 abort；
- AIMAPP 返回上一认知位置；
- 随后重新规划和尝试。

进一步检查原作者：

`potential_field_action.py`

后确认，其运动执行属于较简单的人工势场式局部控制。

整体逻辑主要包括：

- 目标位置产生吸引作用；
- LiDAR 障碍产生排斥作用；
- 两者组合得到期望运动方向；
- 方向误差较大时先原地旋转；
- 方向满足条件后向前运动；
- 一段时间没有明显移动则判定失败。

因此墙边、转角和局部复杂障碍区域的振荡或卡顿具有明显的底层运动控制原因。

由此形成一个重要判断：

**机器人没有顺利走到目标，不等价于 AIMAPP 的主动推断高层决策选择错误。**

需要区分：

高层决定“去哪里”，

与：

底层决定“怎么到那里”。

---

## 6. 开展 Potential Field → Nav2 最小变量对照

为了判断此前观察到的墙边问题主要来自 AIMAPP 高层决策还是底层运动执行，进行了运动层最小变量对照。

仅修改：

`main.py`

中的运动客户端。

由：

`self.motion_client = PFClient()`

切换为：

`self.motion_client = Nav2Client()`

当前配置为：

`self.motion_client = Nav2Client()`

`#self.motion_client = PFClient()`

本次切换没有修改：

- 状态推断；
- 认知地图；
- 生成模型；
- Expected Free Energy；
- MCTS；
- 候选动作；
- 高层目标选择。

因此该实验主要用于判断：

**相同的 AIMAPP 高层目标交给不同底层运动执行模块后，实际运动表现是否发生变化。**

---

## 7. Nav2 首次启动时 TF 不完整

启动 Nav2 后发现部分节点不能正常进入 active 状态。

其中：

`controller_server`

持续等待 local costmap 所需的 TF，并报告无法建立：

`odom -> base_link`

变换。

随后逐段检查 TF。

检查：

`odom -> base_footprint`

发现该变换已经存在。

继续检查：

`base_footprint -> base_link`

发现两个坐标系位于断开的 TF tree 中。

同时检查当前 ROS2 节点，只发现 TurtleBot3 joint state 相关节点，没有：

`robot_state_publisher`

因此确认：

通过当前独立的 Gazebo：

`spawn_entity.py`

加载 `waffle_pi_plus` 时，没有自动完成机器人 URDF 对应的 robot state publisher 配置。

---

## 8. robot_state_publisher 第一次配置失败

随后尝试使用 TurtleBot3：

`turtlebot3_waffle_pi.urdf`

启动：

`robot_state_publisher`

第一次直接将 URDF 文件内容作为：

`robot_description`

传入。

虽然节点可以启动，但：

`base_footprint -> base_link`

仍然没有正确连接。

进一步检查参数内容后发现仍存在：

`${namespace}base_footprint`

`${namespace}base_link`

等字符串。

这说明该 TurtleBot3 URDF 文件仍然包含 xacro 表达式，不能直接通过 `cat` 后作为完整 URDF 使用。

---

## 9. 使用 xacro 正确恢复机器人 TF

随后将流程修改为：

TurtleBot3 Waffle Pi URDF

→ `xacro`

→ 完整 `robot_description`

→ `robot_state_publisher`

成功建立：

`base_footprint -> base_link`

固定变换。

最终机器人主要 TF 链恢复为：

`odom -> base_footprint -> base_link`

完成该处理后再次检查 Nav2：

- `controller_server` active；
- `planner_server` active；
- `behavior_server` active；
- `bt_navigator` active；
- `waypoint_follower` active。

说明此前 Nav2 无法正常进入运行状态的主要原因是机器人 TF 链不完整。

---

## 10. AIMAPP Agent 的 tests 工作目录问题

Nav2 正常后启动：

`ros2 launch aimapp agent_launch.py x:=0.0 y:=0.0`

首先出现：

`FileNotFoundError`

错误指向：

`~/aimapp_ws/src/aimapp/tests`

进一步检查原作者：

`agent_launch.py`

发现其启动逻辑默认访问当前工作目录下：

`tests/`

目录。

新的：

`~/aimapp_ws/src/aimapp`

中当时没有该目录。

创建：

`~/aimapp_ws/src/aimapp/tests`

以后，该问题解决。

这一问题属于原作者 launch 文件对于运行目录结构的默认假设，不涉及 AIMAPP 核心算法。

---

## 11. AIMAPP Python 节点 executable 权限问题

解决 `tests/` 目录以后再次启动 AIMAPP，出现：

`executable 'main.py' not found on the libexec directory`

随后检查：

`~/aimapp_ws/install/aimapp/lib/aimapp/`

发现：

`main.py`

以及其他 Python 文件实际上已经通过：

`--symlink-install`

正确链接到源码目录。

例如：

`install/aimapp/lib/aimapp/main.py`

指向：

`src/aimapp/aimapp/aimapp/main.py`

因此不是 CMake 安装缺失。

进一步检查源码文件权限发现：

`main.py`

为：

`-rw-rw-r--`

缺少 executable 位。

随后为以下由 AIMAPP launch 直接启动的 Python 节点增加执行权限：

- `main.py`
- `get_pano_multiple_camera_action.py`
- `potential_field_action.py`
- `align_odom_to_belief.py`

之后 AIMAPP Agent 可以正常启动。

---

## 12. AIMAPP + Nav2 成功运行

完成：

- Nav2 TF 修复；
- `tests/` 目录处理；
- Python executable 权限处理；

以后，AIMAPP Agent 成功启动并开始自主运动。

当前使用：

`Nav2Client()`

作为运动执行层。

Gazebo 中进行单次直观观察后发现，相比原始 Potential Field：

- 墙边运动更加自然；
- 转角附近处理更加平稳；
- 局部障碍附近运动更加合理；
- 原先部分明显的贴墙后反复旋转现象有所减少。

目前该比较仅属于单次定性观察，因此不将其表述为正式的统计性能提升。

但该对照已经能够支持如下判断：

**此前 Potential Field 版本观察到的部分墙边磨蹭、旋转和运动失败与底层运动执行有关，不能全部归因于 AIMAPP 高层主动推断策略。**

---

## 13. 重新厘清“决策”和“路径规划”

结合今日 Nav2 接入过程，对 AIMAPP 中容易混淆的两个层次进行了重新梳理。

AIMAPP / SCA-AIFNav 高层主要解决：

**为什么去，以及下一步应该去哪里。**

主要涉及：

- 当前状态推断；
- 认知地图；
- 对未来状态的预测；
- Expected Free Energy；
- MCTS；
- 信息获取；
- 目标趋近；
- 高层策略选择；
- 输出下一目标。

Nav2 主要解决：

**目标确定以后，机器人如何安全、稳定地到达。**

主要涉及：

- 路径规划；
- costmap；
- 障碍处理；
- 局部避障；
- trajectory evaluation；
- 轨迹跟踪；
- 速度控制；
- recovery behavior。

因此两者都可以涉及 planning，但属于不同层次。

当前可以概括为：

**AIMAPP 决定“去哪”，Nav2 负责“怎么去”。**

---

## 14. 主动推断多目标决策表述重新确认

今日进一步讨论了此前 PPT 和汇报中关于：

“主动推断解决多目标决策，不需要建立各种目标函数或损失函数”

这一表述。

核心研究思想仍然成立，但“完全不需要目标函数或损失函数”的说法过于绝对。

后续更准确的表述确定为：

**主动推断通过期望自由能将目标导向价值与信息价值纳入统一的概率推断框架，在策略选择层面实现探索与利用的协调，减少对多个独立奖励函数及人工权重组合的依赖。**

这里讨论的是高层策略选择问题。

Nav2 内部使用的：

- costmap；
- 障碍代价；
- 路径评价；
- trajectory critic；

属于底层路径规划与控制问题。

因此使用 Nav2 并不会否定主动推断用于多目标策略选择的研究意义。

---

## 15. SCA-AIFNav 后续运动层正式确定为 Nav2

结合：

- AIMAPP 论文架构；
- 原作者公开代码；
- Potential Field 实际运行表现；
- Nav2 实际运行表现；
- 后续 ROS2 实车需求；

今日正式确定：

**后续 SCA-AIFNav 默认采用 Nav2 作为运动执行层。**

系统职责固定为：

### SCA-AIFNav

负责：

- 状态推断；
- 认知地图；
- 空间结构复杂度；
- Expected Free Energy；
- MCTS；
- 高层策略选择；
- 输出下一目标。

### Nav2

负责：

- 路径规划；
- 局部避障；
- 轨迹跟踪；
- 运动控制；
- ROS2 仿真和真实小车执行。

Potential Field 不删除，其用途调整为：

**AIMAPP 原作者公开代码运动执行基线。**

但不再作为 SCA-AIFNav 默认运动模块。

---

## 16. Mini Warehouse 启动基线重新整理

此前为了排查 Gazebo 加载顺序问题，曾建立：

Baseline A

与：

Baseline B

两套启动方法。

随着 Gazebo 长时间加载问题已经定位为：

`GAZEBO_MODEL_PATH`

配置问题，两种启动顺序已经没有继续同时维护的必要。

因此今日删除：

Baseline B

并将：

**Baseline A v2（Nav2）**

固定为 Mini Warehouse 唯一正式启动方式。

当前固定顺序为：

`A1 Gazebo Server`

→

`A2 Gazebo GUI`

→

`A3 Spawn Robot + robot_state_publisher`

→

`A4 Nav2`

→

`A5 AIMAPP Agent`

---

## 17. A1～A5 启动脚本重新固化

当前所有正式启动脚本位于：

`~/AIMAPP-Reproduction/scripts/mini_warehouse/`

包括：

`baseline_A_1_server.sh`

`baseline_A_2_gui.sh`

`baseline_A_3_spawn_robot.sh`

`baseline_A_4_nav2.sh`

`baseline_A_5_agent.sh`

所有脚本已经从旧工作区：

`~/aimapp_reproduction_ws`

统一切换到：

`~/aimapp_ws`

### A1 — Gazebo Server

负责：

- 加载 ROS2 Humble；
- 加载当前 `aimapp_ws` overlay；
- 获取 Mini Warehouse 路径；
- 获取 TurtleBot3 Gazebo 路径；
- 正确设置 `GAZEBO_MODEL_PATH`；
- 启动 `gzserver`。

该脚本中保留：

`turtlebot3_gazebo/models`

从而避免此前 mesh 资源查找异常。

### A2 — Gazebo GUI

负责：

- 使用与 A1 相同的环境配置；
- 启动 `gzclient`；
- 显示 Mini Warehouse。

### A3 — Spawn Robot + TF

负责：

- spawn AIMAPP `turtlebot3_waffle_pi_plus`；
- 使用 TurtleBot3 Waffle Pi URDF；
- 通过 xacro 展开 robot description；
- 启动 `robot_state_publisher`；
- 提供 `base_footprint -> base_link`。

该终端启动后需要持续保持运行。

### A4 — Nav2

负责：

`ros2 launch aimapp nav2_humble_launch.py`

作为 AIMAPP 的底层运动规划与控制模块。

### A5 — AIMAPP Agent

负责：

- 创建 `agent_launch.py` 所需 `tests/`；
- 确保关键 Python ROS2 节点具有 executable 权限；
- 检查当前 `main.py` 是否启用 `Nav2Client()`；
- 从正确的 AIMAPP 源码目录启动：
  `agent_launch.py`。

全部 A1～A5 脚本已经执行：

`bash -n`

语法检查。

结果：

**全部通过。**

---

## 18. 当前 Mini Warehouse 固定启动方式

截至今日，后续 Mini Warehouse AIMAPP + Nav2 统一按照以下顺序启动：

### Terminal 1

`baseline_A_1_server.sh`

### Terminal 2

`baseline_A_2_gui.sh`

### Terminal 3

`baseline_A_3_spawn_robot.sh`

### Terminal 4

`baseline_A_4_nav2.sh`

### Terminal 5

`baseline_A_5_agent.sh`

该启动方式已经替代此前所有 A/B 混合方式。

详细启动说明单独保存在：

`docs/baselines/MINI_WAREHOUSE_STARTUP_BASELINE.md`

---

## 19. AIMAPP 结果后处理代码初步审计

在运行环境排查之外，今日还继续检查了原作者：

`aimapp/tests/plot_results.ipynb`

结果后处理代码。

目前记录到几个需要重点核查的位置。

### Coverage-Distance 距离累计

在：

`get_coverage_over_dist_and_distance()`

的 fallback 逻辑中发现距离增量使用：

`dx**2 + dy**2`

直接累计。

从函数注释和变量意义看，如果这里理论上表示 Euclidean distance，则通常应计算平方根。

当前先记录为待正式审计问题，没有直接修改官方 notebook。

### GBPlanner 距离计算

在：

`gbplan_get_coverage_over_dist_and_distance()`

中发现类似平方距离累计方式。

部分逻辑还将该量直接与：

`step_m`

比较。

如果前者实际单位为平方距离而后者单位为 m，则可能存在量纲问题，需要结合作者数据格式进一步确认。

### Coverage-Distance 横坐标

部分绘图逻辑使用：

`np.arange(...)`

形成横坐标，同时标记为：

`Distance Travelled (m)`

需要继续核查前置采样是否保证一个 index 对应固定实际距离。

### Notebook 变量引用

部分 Home–GBPlanner metric 单元中观察到疑似引用 Big Warehouse 变量的情况。

目前仅记录为代码审计线索。

在确认其是否参与作者正式论文结果之前，不据此直接判断论文定量结果存在错误。

---

## 20. 截至今日实际完成事项

截至 2026-09-10，已经实际完成：

- AIMAPP 官方 commit 固定；
- 官方只读审计副本建立；
- 新 `aimapp_ws` 运行工作区建立；
- `reproduction` 分支建立；
- AIMAPP ROS2 package 编译成功；
- Mini Warehouse Gazebo 长时间加载问题定位；
- `GAZEBO_MODEL_PATH` 修正；
- `waffle_pi_plus` 正常 spawn；
- 原始 Potential Field AIMAPP 完整自主闭环验证；
- Potential Field 墙边异常行为分析；
- AIMAPP 运动层切换为 Nav2；
- Nav2 TF 缺失问题定位；
- `robot_state_publisher` 缺失问题定位；
- TurtleBot3 URDF xacro 展开问题定位；
- `base_footprint -> base_link` TF 修复；
- Nav2 核心 lifecycle 节点进入 active；
- AIMAPP `tests/` 目录问题解决；
- ROS2 Python executable 权限问题解决；
- AIMAPP + Nav2 成功自主运行；
- PF 与 Nav2 完成一次定性对照；
- AIMAPP 高层决策与 Nav2 底层规划概念重新厘清；
- 主动推断多目标决策表述进一步规范；
- SCA-AIFNav 后续默认运动层正式确定为 Nav2；
- Baseline B 删除；
- Mini Warehouse A1～A5 唯一启动基线建立；
- 所有启动脚本统一切换至 `~/aimapp_ws`；
- A1～A5 Bash 语法检查全部通过；
- AIMAPP 结果后处理 notebook 初步审计继续推进。

以上为截至 2026-09-10 的工作记录。

---

# 2026-09-11 工作记录

## 21. AIMAPP 运行依赖补齐与 Baseline A v2 验证

在整理 AIMAPP 正式运行环境时发现，新工作区仍隐式依赖旧 `~/aimapp_reproduction_ws`。进一步检查确认，Mini Warehouse 所需的 `aws_robomaker_small_warehouse_world` 仅存在于旧工作区，因此新工作区独立启动时会出现 package not found。随后将该 package 迁移至正式 AIMAPP 运行工作区并构建成功。

继续对比旧工作区 package 组成后发现，`aws_robomaker_small_house_world` 同样属于旧工作区独有环境资源，因此一并迁移并完成构建。当前正式 AIMAPP 工作区包含 `aimapp`、`aimapp_actions`、`aws_robomaker_small_house_world` 和 `aws_robomaker_small_warehouse_world`。

旧工作区额外存在的 TurtleBot3 simulation 相关 package 未继续复制。当前 Baseline A v2 已验证可直接使用系统 `/opt/ros/humble` 中安装的 `turtlebot3_gazebo`，因此不再依赖旧 workspace 中的重复副本。

在目录重构前，重新从 A1 至 A5 完整启动 Mini Warehouse。Gazebo Server、Gazebo GUI、TurtleBot3 spawn 与 `robot_state_publisher`、Nav2、AIMAPP Agent 均正常工作。Nav2 lifecycle 节点最终进入 active，AIMAPP Agent 正常启动 `Nav2Client`、初始化位姿、获取全景观测并开始自主导航。因此 Mini Warehouse + Nav2 Baseline A v2 已完成完整运行验证。

## 22. AIMAPP 原始运行结果归档

检查正式 AIMAPP 源码树时发现，`tests/0/` 和 `tests/1/` 中已经产生运行结果文件，包括 `steps_data.csv` 和 `model.pkl`。

为避免后续实验覆盖原始结果，将两组数据原样复制至：

`results/raw/2026-09-10_aimapp_runtime_snapshot/`

当前归档内容为：

- `0/model.pkl`
- `0/steps_data.csv`
- `1/model.pkl`
- `1/steps_data.csv`

目前没有充分证据确认目录 `0` 和 `1` 分别对应 PF 或 Nav2，因此暂不对两组结果进行方法标签推断，仅作为原始运行快照保存。

## 23. AIMAPP 与 SCA-AIFNav 项目目录统一重构

此前 AIMAPP 与 SCA-AIFNav 相关工作区分散在 Home 目录下，不利于后续维护。今日建立统一总项目目录：

`~/SCA-AIFNav-Project/`

当前主要结构为：

```text
SCA-AIFNav-Project/
├── aimapp/
│   ├── runtime_ws/
│   ├── reproduction/
│   ├── audit/
│   └── archive/
│       └── aimapp_reproduction_ws_old/
└── sca_aifnav/
    ├── runtime_ws/
    └── legacy_ws/
```

其中：

- `aimapp/runtime_ws`：当前正式 AIMAPP 运行工作区；
- `aimapp/reproduction`：AIMAPP 复现记录、脚本、文档与实验结果；
- `aimapp/audit`：原作者代码只读审计副本及审计辅助文件；
- `aimapp/archive/aimapp_reproduction_ws_old`：早期 AIMAPP 复现工作区，仅作为历史备份；
- `sca_aifnav/runtime_ws`：当前正式 SCA-AIFNav 工作区；
- `sca_aifnav/legacy_ws`：早期 SCA-AIFNav 工作区。

原 Home 目录下的 `AIMAPP-Reproduction`、`aimapp_reproduction_audit`、`aimapp_reproduction_ws`、`aimapp_ws`、`sca_aifnav_ws`、`sca_aifnav_legacy_ws` 均已完成迁移，不再作为顶层工作目录存在。

旧 `aimapp_reproduction_ws` 当前约占 3.8 GB，已归档至 `aimapp/archive/aimapp_reproduction_ws_old`，暂不删除。后续不再 source、不再编译，也不再作为正式运行依赖。

## 24. 搬迁后的路径修正、环境清理与工作区重建

目录迁移完成后，同步修改当前仍在使用的 README、Mini Warehouse 启动基线文档以及 A1～A5 启动脚本。

正式路径统一调整为：

- AIMAPP 运行工作区：`~/SCA-AIFNav-Project/aimapp/runtime_ws`
- AIMAPP 复现仓库：`~/SCA-AIFNav-Project/aimapp/reproduction`
- AIMAPP 官方审计副本：`~/SCA-AIFNav-Project/aimapp/audit/aimapp_ref`
- SCA-AIFNav 正式工作区：`~/SCA-AIFNav-Project/sca_aifnav/runtime_ws`

A1～A5 启动脚本中的旧 `$HOME/aimapp_ws` 路径已全部更新，并重新执行 Bash 语法检查，五个脚本均通过。

由于 ROS2/colcon 的 `build`、`install`、`log` 及环境变量中可能保留 workspace 的绝对路径，因此目录不能仅移动后继续沿用原有构建产物。首先对 AIMAPP 正式运行工作区删除旧 `build/install/log`，随后在新路径重新执行 `colcon build --symlink-install`。

正式 AIMAPP 工作区四个 package 均重新构建成功：

- `aimapp`
- `aimapp_actions`
- `aws_robomaker_small_house_world`
- `aws_robomaker_small_warehouse_world`

首次重建时，colcon 提示环境变量中仍存在旧 `/home/mars/aimapp_ws` 路径。进一步排查发现，旧 ROS2 overlay 不仅残留在 `AMENT_PREFIX_PATH`、`COLCON_PREFIX_PATH` 和 `CMAKE_PREFIX_PATH`，还存在于 `PYTHONPATH`、`LD_LIBRARY_PATH` 和 `GAZEBO_MODEL_PATH`。

检查 `.bashrc`、`.profile` 等 shell 启动文件后，没有发现写死的旧 AIMAPP workspace 路径。因此问题确定为当前终端会话继承的历史 overlay 环境，而不是永久 shell 配置错误。

随后清理相关 ROS2/colcon/Python/Gazebo 环境变量，仅重新加载 `/opt/ros/humble/setup.bash`，删除 AIMAPP `build/install/log` 后再次干净构建。

最终验证结果：

- 四个 AIMAPP package 均构建成功；
- `ros2 pkg prefix` 全部指向 `~/SCA-AIFNav-Project/aimapp/runtime_ws/install/`；
- 当前环境变量中不存在 `/home/mars/aimapp_ws`；
- 新 `build/install` 中不存在 `/home/mars/aimapp_ws` 或旧 `aimapp_reproduction_ws` 路径。

随后对 SCA-AIFNav 正式工作区执行同样的搬迁后重建。当前工作区包含：

- `sca_aifnav_core`
- `sca_aifnav_ros`
- `sca_aifnav_sim`

三个 package 均在新路径下构建成功，SCA-AIFNav 源码 Git 状态保持干净。

旧路径扫描过程中，`build/sca_aifnav_core/.../__pycache__/*.pyc` 等二进制缓存仍可匹配旧 `/home/mars/sca_aifnav_ws` 路径。进一步排查确认，真正的源码文本中不存在旧 `sca_aifnav_ws` 或 `aimapp_ws` 路径，因此该现象来自 Python 字节码缓存内部保存的历史源码路径，而不是源码配置错误。

随后统一清理 SCA-AIFNav 源码树、build 和 install 中的 `__pycache__`、`*.pyc`、`*.pyo` 文件。再次检查后，缓存和旧路径匹配均为空，源码 Git 状态仍保持干净。

当前 SCA-AIFNav `.gitignore` 已包含 `__pycache__/`、`*.py[cod]` 和 `.pytest_cache/`，因此无需新增规则。

至此，AIMAPP 与 SCA-AIFNav 两个正式 runtime workspace 均已完成新路径下的干净重建和旧路径排查。

需要特别说明：目录重构之后目前完成的是构建、package prefix、环境变量和路径级验证，尚未在新的统一目录结构下再次完整执行 A1～A5 自主导航闭环。此前完整的 Mini Warehouse + Nav2 Baseline A v2 运行验证是在本次目录重构之前完成的。

## 25. 截至 2026-09-11 当前状态

截至本次工作结束，已经实际完成：

- Mini Warehouse Gazebo 启动延迟根因定位与 `GAZEBO_MODEL_PATH` 修复；
- AIMAPP 原始 Potential Field 自主闭环验证；
- AIMAPP 运动层切换至 Nav2；
- Nav2 所需 `base_footprint -> base_link` TF 问题修复；
- Mini Warehouse A1～A5 Baseline A v2 建立；
- 目录重构前完成 A1～A5 + Nav2 完整运行验证；
- AWS Small Warehouse world package 从旧工作区迁移至正式工作区；
- AWS Small House world package 从旧工作区迁移至正式工作区；
- 正式 AIMAPP workspace 已不再依赖旧 `aimapp_reproduction_ws`；
- `tests/0` 与 `tests/1` 原始运行结果已归档至 `results/raw/2026-09-10_aimapp_runtime_snapshot/`；
- AIMAPP、复现仓库、审计副本、SCA-AIFNav 与历史工作区已统一整理到 `~/SCA-AIFNav-Project/`；
- README、启动基线文档和 A1～A5 脚本均更新至新路径；
- AIMAPP runtime workspace 已在新路径完成干净重建；
- SCA-AIFNav runtime workspace 已在新路径完成干净重建；
- ROS2 历史 overlay 环境污染已定位并清除；
- SCA-AIFNav 源码文本不存在旧 workspace 绝对路径；
- SCA-AIFNav Python 字节码缓存已清理；
- 旧 `aimapp_reproduction_ws` 已归档至 `aimapp/archive/aimapp_reproduction_ws_old`，暂不删除。

当前统一项目根目录为：

`~/SCA-AIFNav-Project/`

下一次正式运行验证时，应从新目录重新执行 A1～A5，以完成目录迁移后的最终运行级确认。在该验证完成前，不删除 `aimapp/archive/aimapp_reproduction_ws_old`。

后续 AIMAPP 复现工作继续以定量重复实验、结果后处理审计和正式 reproduction protocol 为主。

---

# 2026-09-11 目录迁移后运行验证补充记录

## 26. Mini Warehouse 新目录运行验证与隐藏依赖修复

在统一目录结构下重新执行 A1～A5 时，A3 首次启动失败。排查确认系统 `/opt/ros/humble/share/turtlebot3_gazebo/models/` 中不存在 AIMAPP 使用的 `turtlebot3_waffle_pi_plus`，该模型此前仅存在于旧 `aimapp_reproduction_ws` 的 TurtleBot3 simulation 源码中。

进一步对比发现，`turtlebot3_waffle_pi_plus` 并非标准 `turtlebot3_waffle_pi` 的简单重命名。AIMAPP 定制模型增加了前、左、右三路相机，并修改了激光雷达量程等配置，因此不能直接替换为系统标准模型，否则会改变 AIMAPP 的观测条件。

模型本体约 80 KB，其引用的 `waffle_pi_base.dae`、`lds.dae` 和 `tire.dae` 等 mesh 已存在于系统 `turtlebot3_gazebo` 安装目录，因此无需迁移完整的旧 TurtleBot3 simulation package。

最终仅提取 AIMAPP 所需的 `turtlebot3_waffle_pi_plus` 模型，并纳入 reproduction 仓库：

`assets/gazebo_models/turtlebot3_waffle_pi_plus/`

同时修改 `baseline_A_3_spawn_robot.sh`，改为使用相对于 reproduction 仓库的模型路径，不再依赖旧 workspace 或固定的 `/home/mars/...` 模型绝对路径。

修改后重新执行 A1～A5，Gazebo、机器人 spawn、Nav2 和 AIMAPP Agent 均正常运行，机器人能够正常开始自主导航。

进一步检查确认：当前环境变量中不存在旧 AIMAPP workspace；AIMAPP、aimapp_actions 以及两个 AWS world package 均来自新的 `~/SCA-AIFNav-Project/aimapp/runtime_ws/install/`；当前脚本和 runtime 源码中不存在 `aimapp_reproduction_ws_old`、`aimapp_reproduction_ws` 或旧 `/home/mars/aimapp_ws` 路径引用。

因此可以确认：统一目录迁移后的 Mini Warehouse + AIMAPP + Nav2 完整运行闭环验证通过，正式运行环境已解除对旧 `aimapp_reproduction_ws_old` 的运行依赖。

---

# 2026-09-11 目录迁移后运行验证补充记录

## 26. Mini Warehouse 新目录运行验证与隐藏依赖修复

在统一目录结构下重新执行 A1～A5 时，A3 首次启动失败。排查确认系统 `/opt/ros/humble/share/turtlebot3_gazebo/models/` 中不存在 AIMAPP 使用的 `turtlebot3_waffle_pi_plus`，该模型此前仅存在于旧 `aimapp_reproduction_ws` 的 TurtleBot3 simulation 源码中。

进一步对比发现，`turtlebot3_waffle_pi_plus` 并非标准 `turtlebot3_waffle_pi` 的简单重命名。AIMAPP 定制模型增加了前、左、右三路相机，并修改了激光雷达量程等配置，因此不能直接替换为系统标准模型，否则会改变 AIMAPP 的观测条件。

模型本体约 80 KB，其引用的 `waffle_pi_base.dae`、`lds.dae` 和 `tire.dae` 等 mesh 已存在于系统 `turtlebot3_gazebo` 安装目录，因此无需迁移完整的旧 TurtleBot3 simulation package。

最终仅提取 AIMAPP 所需的 `turtlebot3_waffle_pi_plus` 模型，并纳入 reproduction 仓库：

`assets/gazebo_models/turtlebot3_waffle_pi_plus/`

同时修改 `baseline_A_3_spawn_robot.sh`，改为使用相对于 reproduction 仓库的模型路径，不再依赖旧 workspace 或固定的 `/home/mars/...` 模型绝对路径。

修改后重新执行 A1～A5，Gazebo、机器人 spawn、Nav2 和 AIMAPP Agent 均正常运行，机器人能够正常开始自主导航。

进一步检查确认：当前环境变量中不存在旧 AIMAPP workspace；AIMAPP、aimapp_actions 以及两个 AWS world package 均来自新的 `~/SCA-AIFNav-Project/aimapp/runtime_ws/install/`；当前脚本和 runtime 源码中不存在 `aimapp_reproduction_ws_old`、`aimapp_reproduction_ws` 或旧 `/home/mars/aimapp_ws` 路径引用。

因此可以确认：统一目录迁移后的 Mini Warehouse + AIMAPP + Nav2 完整运行闭环验证通过，正式运行环境已解除对旧 `aimapp_reproduction_ws_old` 的运行依赖。
