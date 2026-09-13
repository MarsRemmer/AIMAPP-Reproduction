# SCA-AIFNav / AIMAPP 实验坑点与固定结论

本文件只记录已经定位的问题、稳定解决方法以及容易再次踩到的工程坑。

日常“今天做了什么”不写在这里，统一写入：

```text
docs/daily/
```

项目最终完成时，再依据 daily records、本文和 Git 历史统一生成正式 README 与复现说明。

---

## 1. Mini Warehouse Gazebo 启动异常变慢

### 现象

Mini Warehouse 启动后 Gazebo 可能等待数分钟，机器人模型或 mesh 不能及时正常加载。

### 根因

启动脚本覆盖 `GAZEBO_MODEL_PATH` 时遗漏：

```text
turtlebot3_gazebo/models
```

导致 `waffle_pi_plus` SDF 中的：

```text
model://turtlebot3_common/...
```

资源无法正常解析。

### 固定处理

A1/A2 启动环境必须同时包含 TurtleBot3 Gazebo models 与 AWS warehouse models。

### 结论

这不是 AIMAPP 正常初始化耗时，也不是算法性能问题。

---

## 2. Nav2 启动但 lifecycle 节点无法正常 active

### 现象

Nav2 local costmap / controller 等持续等待 TF：

```text
odom -> base_link
```

### 根因

独立使用 `spawn_entity.py` 时没有自动提供完整的 robot state publisher。

当时已有：

```text
odom -> base_footprint
```

但缺少：

```text
base_footprint -> base_link
```

### 固定处理

A3 必须：

```text
TurtleBot3 Waffle Pi URDF
-> xacro
-> robot_description
-> robot_state_publisher
```

不能直接 `cat` 原始 URDF，因为其中仍存在 xacro 表达式。

---

## 3. 不要用标准 waffle_pi 替换 AIMAPP waffle_pi_plus

AIMAPP Mini Warehouse 使用的自定义：

```text
turtlebot3_waffle_pi_plus
```

包含 AIMAPP 所需的前、左、右三路相机及对应 LiDAR 配置。

正式实验模型保存在：

```text
assets/gazebo_models/turtlebot3_waffle_pi_plus/
```

标准 ROS2 Humble `turtlebot3_waffle_pi` 不能直接作为等价替代。

---

## 4. AIMAPP 原生输出不能写回源码目录

### 原因

官方 `agent_launch.py / main.py` 会根据当前工作目录访问并生成：

```text
tests/
```

长期直接在 AIMAPP 源码目录运行会污染 runtime repository，并产生大型实验文件。

### 固定处理

formal runner 为 AIMAPP 设置：

```text
AIMAPP_RUN_CWD=<formal run>/aimapp_native
```

AIMAPP 原生输出因此与对应 trial 放在一起，源码工作区保持独立。

---

## 5. AIMAPP baseline 不是“修改后的新算法”

正式 AIMAPP baseline 定义为：

```text
official AIMAPP 213a4dc
+ Nav2 motion backend selection only
```

本地冻结 commit：

```text
20746e05ab87ec8a63c969a81c99213704769183
```

唯一内容差异：

```text
self.motion_client = PFClient()
```

切换为：

```text
self.motion_client = Nav2Client()
```

对应 patch：

```text
configs/baselines/AIMAPP_NAV2_BACKEND.patch
```

该变化只统一低层运动后端，不改变 AIMAPP 高层主动推断算法。

---

## 6. 高层决策失败与底层运动失败必须区分

AIMAPP / SCA-AIFNav 主要回答：

```text
为什么去、下一步去哪里
```

Nav2 主要回答：

```text
目标确定后如何安全到达
```

因此机器人在墙边、转角或局部障碍附近卡顿，不能直接归因于主动推断高层决策错误。

早期 Potential Field 版本出现的部分墙边振荡和卡顿已经证明属于底层运动执行因素。

---

## 7. SCA posterior 不能直接做概率乘积后再归一化

### 旧问题

SCA 曾在 posterior inference 中直接计算概率乘积。

概率项非常小时可能全部数值下溢为 0，最终触发：

```text
posterior cannot be normalized
```

### 固定处理

与官方 AIMAPP 对齐，采用 epsilon + log-space inference。

当前正式 SCA commit：

```text
3337697
```

不要重新改回直接概率乘积实现。

---

## 8. Coverage 必须与 occupancy confidence 解耦

正式 coverage 定义：

```text
ever_observed_lidar_cells
```

一个网格只要被有效 LiDAR ray 直接观测过，就进入 coverage 集合。

是否已经达到 occupied hit threshold 只影响 occupancy classification，
不能影响该网格是否“已经被观察”。

正式固定参数：

```text
resolution        0.05 m
canvas            40 m x 40 m
max LiDAR range   12 m
TF timestamp      scan header timestamp
```

Coverage Monitor 是外部 evaluator，不参与策略选择。

---

## 9. 非零起点时必须区分物理 odom 与认知坐标

正式 paired experiment 使用多个不同物理起点。

Gazebo `/odom` 反映物理坐标，而 AIMAPP/SCA 内部认知坐标可以从局部原点开始。

因此：

```text
physical start pose
```

与：

```text
agent cognitive odom
```

不能机械认为应该数值完全相同。

正式 start poses 保存在：

```text
configs/mini_warehouse/start_poses.csv
```

---

## 10. 正式实验停止条件不要再与 Coverage 阈值混合

当前 baseline equivalence experiment 固定：

```text
200 completed high-level actions
```

Coverage 只作为评价数据。

不要再使用 95% Cmax 等 coverage 阈值提前结束正式 trial。

---

## 11. Panorama 失败不能通过随意降低标准绕过

官方 AIMAPP panorama 流程本身允许多次重试并逐步降低匹配阈值。

如果最终仍然无法生成合法 panorama，该 trial 应按真实失败保留记录。

不要为了提高成功率而：

- 任意增加重试次数；
- 任意降低阈值；
- 绕过视觉观测；
- 人工跳过失败。

这会改变正式 baseline 行为。

---

## 12. 记录文件只保留两类

从 2026-09-11 起，实验仓库中的长期项目记录只保留：

### 每日工作

```text
docs/daily/YYYY-MM/YYYY-MM-DD.md
```

回答：

```text
今天做了什么、验证了什么、形成了什么结论
```

### 坑点与固定结论

```text
docs/TROUBLESHOOTING.md
```

回答：

```text
遇到什么坑、根因是什么、以后应该怎么避免
```

不再为每个小步骤单独创建 reset、audit、integration、baseline summary 等 Markdown 文件。

需要精确追溯时使用 Git commit history。

---

## 13. 待处理：AIMAPP --symlink-install 与 executable mode

当前 A5 启动脚本会对 AIMAPP Python 节点执行 `chmod +x`。

由于当前 AIMAPP runtime 使用 `--symlink-install`，installed executable 实际指向源码文件，
因此该操作会改变源码文件 mode。

这可能使正式 batch 的 source fingerprint 在第一个 AIMAPP run 后发生变化。

**正式 5 x 200 batch 开始前必须解决该问题。**

优先方向：

```text
保持 AIMAPP source 100644
使用非 symlink install 生成可执行的 install copy
A5 不再修改 AIMAPP source mode
```

在该问题验证完成前，不启动正式长批次实验。

---

## 14. ROS 环境已经 source，但 pytest 仍提示找不到 rclpy / geometry_msgs

### 现象

执行：

```bash
source /opt/ros/humble/setup.bash
```

后，单独运行 Python 可以正常导入：

```text
rclpy
geometry_msgs
nav_msgs
sensor_msgs
cv_bridge
```

但随后执行 pytest 时仍出现：

```text
ModuleNotFoundError: No module named 'rclpy'
ModuleNotFoundError: No module named 'geometry_msgs'
...
```

### 根因

测试命令中使用了：

```bash
PYTHONPATH="$PWD/sca_aifnav_core:$PWD/sca_aifnav_ros"
```

这会覆盖 ROS 已经注入的 `PYTHONPATH`，导致 `/opt/ros/humble/...` 等路径丢失。

### 固定处理

运行 ROS 测试时必须保留原有 `PYTHONPATH`：

```bash
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="$PWD/sca_aifnav_core:$PWD/sca_aifnav_ros${PYTHONPATH:+:$PYTHONPATH}" \
python3 -m pytest \
  sca_aifnav_ros/test \
  -q
```

### 结论

如果“单独 import ROS 包成功、pytest 却全部找不到 ROS 包”，优先检查 `PYTHONPATH` 是否被测试命令覆盖，不要误判为 ROS 安装损坏。

---

## 15. 追加测试后出现 flake8 E303，通常只是空行数量问题

### 现象

功能测试全部通过，但 `test_flake8` 单独失败：

```text
E303 too many blank lines (3)
```

### 根因

通过脚本向测试文件尾部追加新测试时，原文件末尾已有换行，再额外拼接多个 `\n`，容易在新函数前形成 3 个空行。

### 固定处理

只删除多余的一行，不修改测试逻辑。

新增测试时优先保证顶层函数之间只有 PEP8 允许的空行数量。

### 结论

`E303` 属于格式错误，不代表算法或测试逻辑失败。先按错误行定位并最小修改，不要因为 lint 失败重构功能代码。

---

## 16. git diff --check 提示 new blank line at EOF

### 现象

测试全部通过，但：

```bash
git diff --check
```

提示：

```text
new blank line at EOF
```

### 根因

自动追加文本时文件末尾留下了多个换行。

### 固定处理

统一将文件结尾规范为“恰好一个换行符”：

```python
text = path.read_text(encoding="utf-8")
path.write_text(
    text.rstrip("\n") + "\n",
    encoding="utf-8",
)
```

### 结论

正式 commit 前固定执行：

```bash
git diff --check
```

必须无输出后再提交。

---

## 17. git diff --stat 默认不会统计 untracked 新文件

### 现象

新增：

```text
navigation_mode.py
```

后，`git status` 能看到：

```text
?? sca_aifnav_core/sca_aifnav_core/navigation_mode.py
```

但普通：

```bash
git diff --stat
```

没有显示这个文件。

### 根因

`git diff` 默认只比较已跟踪文件的工作区变化，不包含尚未 `git add` 的 untracked 文件。

### 固定处理

审计变更时不要只看 `git diff --stat`，必须同时检查：

```bash
git status --short
git diff --stat
```

提交前再通过 `git add` 将新文件纳入 staged diff。

---

## 18. 导航模式切换不能把旧 executed_action_id 带入“纯重规划” decision

### 现象

运行时从探索模式切换到目标模式，或从目标模式切回探索模式时，会基于当前状态重新执行 MCTS。

早期实现中 `_replan_after_mode_change()` 创建新 `NavigationCoreDecision` 时曾复制：

```text
previous_decision.executed_action_id
```

### 风险

模式切换本身没有执行新物理动作，也没有形成新的“动作 -> 观测 -> 学习”周期。

如果继续携带旧的 `executed_action_id`，实验计数逻辑可能把之前已经完成并计数的动作再次视为新完成动作，造成重复计数。

### 固定处理

纯模式切换 / 纯重规划产生的新 decision 必须：

```text
executed_action_id = None
```

同时：

```text
_cycle_count
```

不得因为模式切换而增加。

### 结论

必须严格区分：

```text
真实物理动作完成后的 decision
```

与：

```text
仅因偏好/模式变化产生的 replanning decision
```

后者绝不能伪装成新的执行经验。

---

## 19. NavigationNode 与 NavigationCoreBridge 的 decision 缓存必须同步

### 现象

`NavigationCoreBridge` 内部维护：

```text
_latest_decision
```

`NavigationNode` 同时也维护：

```text
_latest_navigation_decision
```

如果只在 Bridge 中切换模式并重新规划，而 Node 没同步更新，两个层级会对“当前决策”产生不同认识。

### 风险

可能出现：

```text
Bridge.next_action_id = 新模式下的新动作
Node.latest_navigation_decision = 旧模式下的旧 decision
```

导致后续执行、日志或生命周期判断使用不同版本的计划。

### 固定处理

运行时模式切换必须通过 Node 层接口统一调用：

```text
set_exploration_navigation(...)
set_goal_navigation(...)
```

Bridge 完成重新规划后，Node 必须同步替换自己的：

```text
_latest_navigation_decision
```

### 结论

Bridge 负责核心状态与规划，Node 负责 ROS 生命周期，但两者暴露的“当前 decision”必须始终一致。

---

## 20. 物理动作执行期间或已完成动作等待观测期间禁止切换导航模式

### 原因

模式切换会替换当前偏好和下一步规划。

如果机器人仍在执行旧计划对应的物理动作，此时切换模式会造成：

```text
物理执行 = 旧动作
内部计划 = 新模式下的新动作
```

两者失配。

同样，如果一个物理动作已经完成，但其结果观测尚未进入模型学习，此时切换模式会打断完整的：

```text
action -> observation -> learning
```

闭环。

### 固定处理

以下两种状态均禁止切换模式：

```text
navigation_action_active == True
```

以及：

```text
_completed_action_id is not None
```

必须先完成当前动作对应的观测与学习，再允许改变模式。

---

## 21. 目标到达后不要自动切回 EXPLORE

### 设计结论

当前目标模式包括：

```text
GOAL_DIRECT
GOAL_BALANCED
```

目标到达后应：

```text
正常完成当前观测学习
-> goal_reached = True
-> next_action_id = None
-> 停止当前自动导航任务
-> 保持当前 GOAL 模式
-> 保持目标偏好
-> 等待新的明确任务指令
```

不要自动执行：

```text
GOAL -> EXPLORE
```

### 原因

“目标已完成”和“用户要求重新探索”是两个不同事件。

自动切换会隐式改变任务语义，也会使实验状态难以解释。

---

## 22. GOAL_DIRECT 只有评价项配置与 AIMAPP 原始目标模式等价

### AIMAPP 原始目标模式

AIMAPP 目标模式的主要评价项配置为：

```text
use_utility = True
use_states_info_gain = False
use_inductive_inference = True
```

SCA-AIFNav 中对应：

```text
GOAL_DIRECT
```

### 必须明确的边界

以下内容属于 SCA-AIFNav 工程扩展，不应写成 AIMAPP 原样复现：

```text
GOAL_BALANCED
place goal 接口
运行时模式切换
目标到达后的停止/等待生命周期
Node-Bridge decision cache 同步
```

其中 `GOAL_BALANCED` 为：

```text
utility = True
state information gain = True
inductive inference = True
```

用于后续探索-目标平衡比较与消融。

---

## 23. 参数信息增益暂不加入正式模式

### AIMAPP 情况

AIMAPP 实现了基于：

```text
pA
pB
```

的 parameter information gain，但正式探索模式与正式目标模式均设置：

```text
use_param_info_gain = False
```

其 MCTS 实现中还对该项额外进行：

```text
/ 100
```

尺度压缩，并留有其与其他项联合使用效果不佳的源码注释。

### 当前固定结论

现阶段 SCA-AIFNav 三种模式均不启用参数信息增益。

当前只稳定使用：

```text
State Information Gain
Expected Utility
Inductive Inference
```

Parameter Information Gain 后续作为独立 AIMAPP 等价性审计项处理，完成准确复现后再决定是否加入实验消融。

不要为了“评价项更完整”而直接把它打开，否则会改变当前已冻结的探索与目标导航基线。

---

## 24. 2026-09-13 导航模式最终固定定义

当前三种模式统一定义为：

### EXPLORE

```text
use_utility = False
use_state_information_gain = True
use_inductive_inference = False
```

用途：AIMAPP 对齐的纯探索模式。

### GOAL_DIRECT

```text
use_utility = True
use_state_information_gain = False
use_inductive_inference = True
```

用途：AIMAPP 对齐的直接目标导航基线。

### GOAL_BALANCED

```text
use_utility = True
use_state_information_gain = True
use_inductive_inference = True
```

用途：SCA-AIFNav 扩展的目标-信息平衡模式。

不要再通过散落的三个 bool 临时组合运行正式实验，统一通过命名模式配置，避免实验条件失控。
