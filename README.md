# AIFNav Experiment Harness

本仓库只负责 AIMAPP 与 SCA-AIFNav 的统一实验基础设施。

算法源码分别位于：

```text
~/SCA-AIFNav-Project/aimapp
~/SCA-AIFNav-Project/sca_aifnav
```

实验结果统一位于：

```text
~/SCA-AIFNav-Project/results
```

## 当前目录

```text
experiments/
├── assets/              # 仿真运行所需静态资源
├── configs/             # 起点、baseline patch 等实验配置
├── docs/
│   ├── daily/           # 每日工作记录
│   └── TROUBLESHOOTING.md
└── scripts/
    └── mini_warehouse/  # Mini Warehouse 实验脚本
```

当前阶段不再增加其他过程型 README 或零散说明文档。

## 记录规则

项目过程只长期维护两类记录：

1. `docs/daily/`：每天完成了什么；
2. `docs/TROUBLESHOOTING.md`：解决过哪些坑，以及以后如何避免。

项目结束时再结合上述记录、Git 历史和正式实验结果重新生成最终版 README 与复现文档。

## 当前正式基线

```text
AIMAPP official       213a4dc
AIMAPP + Nav2         20746e0
SCA-AIFNav            3337697
```

AIMAPP + Nav2 相对官方 AIMAPP 唯一算法运行差异为低层 motion client 从
`PFClient` 切换为 `Nav2Client`。

## Mini Warehouse 正式实验

核心入口：

```text
scripts/mini_warehouse/run_formal_paired_batch.sh
```

正式停止条件：

```text
200 completed high-level actions
```

每个环境目标获得至少 5 个完整 paired successful runs。

Coverage 使用独立 ever-observed evaluator，只用于评价，不反馈给算法。

> 注意：正式长批次开始前，仍需解决 `--symlink-install` 下 A5 修改
> AIMAPP Python 文件 executable mode 导致 source fingerprint 变化的问题。
