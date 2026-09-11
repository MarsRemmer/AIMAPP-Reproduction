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
