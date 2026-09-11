# SCA-AIFNav-Project 目录重构与清理记录

**日期：2026年9月11日**

## 一、重构目的

此前 AIMAPP 目录同时承担算法源码、复现脚本、公共实验 runner、
SCA 对比脚本和实验评价工具，而根目录 `experiments/` 实际保存实验结果。
本次重构将算法、实验基础设施和实验输出彻底分离。

## 二、重构后的职责

- `aimapp/`：只负责 AIMAPP runtime；
- `sca_aifnav/`：只负责 SCA-AIFNav runtime；
- `experiments/`：负责统一启动、记录、评价和实验配置；
- `results/`：只保存实验产生的数据。

## 三、当前源码版本

AIMAPP runtime：

```text
213a4dc
```

SCA-AIFNav：

```text
3337697
```

重构前 experiment harness：

```text
a09b19b
```

## 四、删除的历史内容

删除或清理：

- `aimapp/audit/`；
- `aimapp/archive/`；
- `sca_aifnav/legacy_ws/`；
- Python / pytest cache；
- 被后续版本替代的 Coverage Monitor V1/V2/V3 中间 smoke；
- visualization demo / retry；
- pre-ever-observed reference；
- 旧 50-action calibration；
- 旧 reference evaluator 文件。

## 五、长期保留的代表性验证结果

保留：

```text
results/mini_warehouse/validation/
├── aimapp_nonzero_start/
├── sca_nonzero_start/
├── coverage_ever_observed/
├── coverage_visualization/
└── reference_coverage/
```

## 六、配置归位

`start_poses.csv` 从结果目录迁移至：

```text
experiments/configs/mini_warehouse/start_poses.csv
```

## 七、Reference Evaluator 收敛

最终 evaluator 文件名统一为：

```text
reference_coverage_probe.py
prepare_reference_coverage.sh
```

历史版本不再通过 V1/V2/V3/V4 文件名长期并存，历史变化交由 Git 管理。

## 八、验证

重构后已执行：

- Shell syntax check；
- Python compile check；
- Git diff check；
- Mini Warehouse formal runner preflight。

## 九、空间变化

重构前：

```text
1.6G
```

重构后：

```text
354M
```

约释放：

```text
1.2GiB
```

## 十、最终原则

> AIMAPP 只负责 AIMAPP。
> SCA-AIFNav 只负责 SCA-AIFNav。
> experiments 负责如何启动、记录和评价。
> results 负责保存实验产生的数据。
