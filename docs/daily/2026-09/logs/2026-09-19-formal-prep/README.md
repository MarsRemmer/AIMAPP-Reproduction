# 2026-09-19 Formal-run preparation logs

本目录记录 2026-09-19 Mini Warehouse 正式长跑准备阶段的关键验证结果和易踩坑点。

大型 rosbag、MP4、PNG、NPZ 以及完整模型文件继续保存在本机 `results/`，不上传 GitHub。

## AIMAPP model retention

正式工具：

```text
scripts/mini_warehouse/aimapp_model_retention.py
```

正式默认：

```text
keep_every = 50
interval   = 5 s
```

关键原则：

```text
按 step number 判断最新模型
不能按 mtime 判断实验进度
不删除 model_temp.pkl
不删除 run-level model.pkl
不删除 CSV / panorama / coverage / rosbag
```

假数据测试：

```text
RETENTION TEST: PASS
WATCH RETENTION TEST: PASS
```

真实 AIMAPP smoke：

```text
results/mini_warehouse/validation/aimapp_retention_real_20260919_080732
max step = 6
REAL RETENTION SMOKE: PASS
```

对应正式提交：

```text
2128f57 feat: bound AIMAPP model snapshot storage
```

## no-progress watchdog

当前本地版本：

```text
NO_PROGRESS_TIMEOUT_SEC = 1800
RUN_TIMEOUT_SEC         = 14400
```

AIMAPP 使用 completed `Next action` 日志作为高层进度。

SCA 不再使用 `Nav2 goal succeeded`，因为 STAY 不经过 Nav2。

## SCA exact progress

新增纯日志：

```text
EXPERIMENT_PROGRESS actions=<n> limit=<limit>
```

真实 2-action smoke：

```text
results/mini_warehouse/validation/sca_progress_2action_20260919_083039
EXPERIMENT_PROGRESS actions=1 limit=2
EXPERIMENT_PROGRESS actions=2 limit=2
EXPERIMENT_COMPLETE actions=2 limit=2
SCA PROGRESS SMOKE: PASS
```

## 当前未提交代码

SCA：

```text
M sca_aifnav_ros/sca_aifnav_ros/navigation_node.py
```

Harness：

```text
M scripts/mini_warehouse/run_formal_paired_batch.sh
```

两处修改当前不要误记为已经 push。

## Shell / ROS 注意事项

ROS setup 前不要开启 `set -u`。使用：

```text
set +u
source /opt/ros/humble/setup.bash
```

当前环境也不能假设裸 `pytest` 命令存在。ROS package regression 使用：

```text
colcon build
colcon test
colcon test-result --verbose
```

## 下一道 gate

```text
SCA full regression
-> commit SCA progress logging
-> commit harness watchdog
-> post-commit preflight
-> 200-action pilot
-> inspect retention/watchdog/coverage/rosbag/video/disk
-> 5 × 200 paired formal runs
```

---

## 状态补正：2026-09-19 后续提交状态

本记录前文保留了开发过程中的“尚未提交”状态，用于反映当时的真实工作阶段。

随后本日已完成以下正式提交并推送：

```text
SCA-AIFNav:
a29db95 feat: expose completed experiment action progress

AIMAPP-Reproduction:
377b7be feat: add no-progress watchdog to formal runs
```

因此截至本次补正：

```text
AIMAPP model retention：已验证、已提交
SCA EXPERIMENT_PROGRESS：已提交
formal no-progress watchdog：已提交
2026-09-19 工作记录：已归档
```

前文关于 retention、mtime、model_temp.pkl、STAY 与 Nav2 success、
ROS setup/set -u 等易踩坑结论继续有效。

下一阶段进入正式长跑前的最终检查及 200-action pilot。
