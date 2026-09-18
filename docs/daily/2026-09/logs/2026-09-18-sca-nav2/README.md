# 2026-09-18 SCA/Nav2 实验链验证日志

> 本轮连续工作实际持续至 2026-09-19 凌晨，统一计入 2026-09-18 工作记录。

## 本轮完成内容

- SCA odom-only Nav2 正式接入实验 harness。
- SCA 速度链固定为 `/cmd_vel_nav -> velocity_smoother -> /cmd_vel`。
- 3-action Nav2 smoke 通过。
- Coverage、distance、visualizer、rosbag recorder 全链路接入。
- recorder 同时记录 `/cmd_vel_nav` 与 `/cmd_vel`，并归档 SCA Nav2 配置。
- 首次完整 10-action 验证通过。
- 定位到目标 `(-0.578, 2.180)` 在 NavFn tolerance=0.1 m 下反复规划失败。
- 该目标距最近已观测障碍约 0.095 m；0.1 m 范围内没有安全替代终点。
- 0.5 m 范围内存在安全替代终点，与 0.5 m cognitive node influence radius 一致。
- 将 SCA NavFn tolerance 从 0.1 m 对齐到 0.5 m。
- 原失败目标针对性验证成功。
- 修正后再次完成完整 10-action 集成验证。

## 关键提交

```text
8abdb75 fix: route SCA motion through Nav2 velocity smoother
f44a249 feat: integrate SCA odom-only Nav2 into experiment harness
29149eb feat: record SCA Nav2 command and configuration
563f386 fix: align NavFn tolerance with cognitive node radius
```

## 两次完整 10-action 验证

```text
修正前：
completed actions = 10
Nav2 goals        = 17
Nav2 succeeded    = 13
Nav2 failed       = 4
known area        = 25.002500 m²
distance          = 7.822620 m

修正后：
completed actions = 10
Nav2 goals        = 12
Nav2 succeeded    = 11
Nav2 failed       = 1
known area        = 25.270000 m²
distance          = 7.044946 m
```

> 两轮轨迹不同，因此上述数字仅用于工程验证，不作为算法性能比较。

## 当前状态

SCA 主执行链已经完成集成验证，暂时冻结。正式长跑前剩余：

1. AIMAPP `model.pkl` 长跑磁盘膨胀控制；
2. formal runner no-progress watchdog；
3. 正式 5 × 200 action paired runs。

大型 rosbag、MP4、PNG、NPZ 等实验产物继续保存在本机 results，不上传 GitHub。
