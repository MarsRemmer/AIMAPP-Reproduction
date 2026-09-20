# SCA-AIFNav-Project 目录结构

从 2026-09-11 起，项目按照“算法、实验、环境、结果”职责分离。

## 1. 总体目录

```text
SCA-AIFNav-Project/
├── aimapp/
│   └── runtime_ws/
│       ├── src/
│       │   ├── aimapp/
│       │   ├── aws-robomaker-small-house-world/
│       │   └── aws-robomaker-small-warehouse-world/
│       ├── build/
│       ├── install/
│       └── log/
│
├── sca_aifnav/
│   └── runtime_ws/
│       ├── src/
│       │   └── sca_aifnav/
│       ├── build/
│       ├── install/
│       └── log/
│
├── experiments/
│   ├── assets/
│   ├── configs/
│   ├── docs/
│   └── scripts/
│
├── results/
│   └── mini_warehouse/
│       ├── validation/
│       ├── formal/
│       ├── processed/
│       └── figures/
│
└── PROJECT_STRUCTURE.md
```

## 2. 各目录职责

- `aimapp/`：AIMAPP 基线算法及 Gazebo 仿真环境运行工作区。
- `sca_aifnav/`：SCA-AIFNav 核心算法、ROS 2 节点及仿真集成工作区。
- `experiments/`：统一负责实验启动、配置、记录、评价和批处理。
- `results/`：只保存实验结果、rosbag、日志、轨迻、覆盖率数据和图像，不上传 Git。
- ROS 2 的 `build/`、`install/`、`log/` 均为本机生成目录。

## 3. Git 仓库

### AIMAPP

- 本地：`aimapp/runtime_ws/src/aimapp`
- GitHub：`https://github.com/MarsRemmer/aimapp.git`
- 分支：`reproduction`
- 当前基线：`20746e0`
- 官方 upstream：`https://github.com/decide-ugent/aimapp.git`

### AWS RoboMaker Small House World

- 本地：`aimapp/runtime_ws/src/aws-robomaker-small-house-world`
- GitHub：`https://github.com/MarsRemmer/aws-robomaker-small-house-world.git`
- 分支：`sca-aifnav-env`
- 当前基线：`13eeab7`
- 官方 upstream：`https://github.com/aws-robotics/aws-robomaker-small-house-world.git`

### AWS RoboMaker Small Warehouse World

- 本地：`aimapp/runtime_ws/src/aws-robomaker-small-warehouse-world`
- GitHub：`https://github.com/MarsRemmer/aws-robomaker-small-warehouse-world.git`
- 分支：`sca-aifnav-env`
- 当前基线：`6baf3ab`
- 官方 upstream：`https://github.com/aws-robotics/aws-robomaker-small-warehouse-world.git`

### SCA-AIFNav

- 本地：`sca_aifnav/runtime_ws/src/sca_aifnav`
- GitHub：`https://github.com/MarsRemmer/SCA-AIFNav.git`
- 分支：`main`
- 当前基线：`a29db95`

### 实验框架

- 本地：`experiments`
- GitHub：`https://github.com/MarsRemmer/AIMAPP-Reproduction.git`
- 分支：`main`
- 当前基线：`dfa2370`

## 4. 项目管理原则

1. 源码、实验脚本和仿真环境修改必须通过 Git 保存。
2. `results/` 不上传 GitHub。
3. `build/`、`install/`、`log/`、`__pycache__/`、`.pytest_cache/` 等生成目录不作为源码保存。
4. 正式实验开始后固定代码版本，不在实验过程中修改源码。
5. 工作站通过 Git 恢复源码，不依赖手工复制。
6. AIMAPP 与两个 AWS RoboMaker 仓库使用自己的 Fork 作为 `origin`，官方仓库作为 `upstream`。
7. SCA-AIFNav 与 experiments 使用 MarsRemmer 名下仓库作为 `origin`。
8. 历史 smoke、retry、重复缓存和旧 build 副本不长期保留。
