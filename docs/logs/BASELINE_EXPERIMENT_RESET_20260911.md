# AIMAPP vs SCA-AIFNav 基线实验重新起算记录

日期：2026-09-11

## 1. 当前阶段

当前进入 AIMAPP 与 SCA-AIFNav 基线重实现一致性验证阶段。

实验目的不是证明 SCA-AIFNav 优于 AIMAPP，而是验证：

> 在相同 Mini Warehouse 环境、机器人模型、Nav2 运动层、
> 主动推断逻辑、MCTS、动作空间、观测方式、算法参数、
> 固定节点影响半径及终止条件下，SCA-AIFNav 基线实现能够
> 复现 AIMAPP 原始实现的整体导航行为与统计特征。

SCA-AIFNav 在该阶段尚不启用结构复杂度自适应节点影响半径。

## 2. 固定实验条件

- World: Mini Warehouse
- Robot: TurtleBot3 waffle_pi_plus
- Motion backend: Nav2
- Start pose: x=0.0, y=0.0
- Baseline node influence radius: 0.5 m
- AIMAPP and SCA share the same A1-A4 simulation/navigation foundation
- Only the A5 high-level algorithm implementation is switched

## 3. 固定版本

- AIMAPP official/runtime:
  213a4dc856b06819964511bdcd94e57db62e0913

- SCA-AIFNav baseline:
  aa0e233e5388ceab1acd445dd83a19f75005ec04

- AIMAPP-Reproduction recorder/layout:
  75c49ac44e4a24543855259ada364e471f471d09

## 4. 工程目录规范

~/SCA-AIFNav-Project/

aimapp/
- audit/          AIMAPP 固定参考、审计、代码对照
- reproduction/   复现脚本、实验工具、文档
- runtime_ws/     当前 AIMAPP ROS2 运行环境

sca_aifnav/
- legacy_ws/      历史工作区，仅保留参考
- runtime_ws/     当前 SCA-AIFNav 开发工作区

experiments/
- mini_warehouse/smoke/      启动、集成、recorder 检查
- mini_warehouse/formal/     正式原始实验数据
- mini_warehouse/processed/  后处理结果
- mini_warehouse/figures/    最终图表
- archive/                   历史实验归档（本次重置后清空）

## 5. 2026-09-11 文件整理结果

完成以下整理：

1. AIMAPP runtime tests/0 与历史快照逐文件 SHA256 校验一致，
   删除重复 runtime 副本。

2. AIMAPP runtime tests/1、tests/2、tests/3 均确认属于未跟踪
   实验运行产物，曾移出源码目录归档。

3. aimapp/reproduction/results/raw 中历史运行结果移出 Git 工程。

4. AIMAPP-Reproduction Git 对象库中历史大型 loose blobs 经
   git prune dry-run 确认可清理后执行 git gc。
   .git 由约 1.1 GB 降至数百 KB。

5. SCA runtime 根目录中的历史实验 CSV 和模型差异文件完成归位。

6. common_run_recorder.sh 已统一改为：
   --check -> experiments/mini_warehouse/smoke/
   正式运行 -> experiments/mini_warehouse/formal/

7. recorder 最终 sanity check 已通过：
   AIMAPP 与 SCA 两种 method 均正确生成 metadata、参数快照、
   topic regex 与启动 topic 信息。

## 6. 历史实验数据处理决定

2026-09-11 决定：

此前所有 AIMAPP/SCA 导航运行均视为开发、调试、复现和
集成验证数据，不纳入正式 AIMAPP-vs-SCA 基线实验统计。

为避免后续数据混淆，旧实验运行结果在本记录保存后清理。

以下内容继续保留：
- Git 源码与历史
- AIMAPP 官方固定参考
- 审计记录
- 复现文档
- 参数与启动脚本
- 算法/机器人模型对照资料

以下内容重新生成：
- rosbag
- trajectory
- coverage
- decision records
- Nav2 goal/result records
- cognitive-map metrics
- timing metrics
- comparison figures

## 7. 新实验编号

从零重新开始。

预实验：

AIMAPP + Nav2
- run_001
- run_002
- run_003

SCA baseline + Nav2
- run_001
- run_002
- run_003

3+3 预实验验证流程稳定后，再进行不少于：

- AIMAPP 10 runs
- SCA baseline 10 runs

正式统计分析。

## 8. 对比指标

主要比较：

- Coverage–Distance
- 最终覆盖率
- 总行驶距离
- 完成时间
- Cognitive node 数量及增长过程
- 高层 action/goal 行为
- Nav2 success/failure
- failure recovery
- cognitive-map structure
- AIF/MCTS 决策逻辑

不要求两种实现轨迹逐点完全相同。

Gazebo、Nav2、ROS callback 时序以及 MCTS 随机性允许产生
单次运行差异，最终判断依据为行为逻辑及统计特征的一致性。

## 9. 实验起点

本记录之后生成的 run_001 才定义为新一轮基线实验数据。

此前运行结果不得与新实验混合统计。
