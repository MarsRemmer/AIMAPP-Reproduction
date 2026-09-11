# AIMAPP + Nav2 基线冻结记录

**日期：2026年9月11日**

## 一、官方基础版本

AIMAPP 正式实验基于官方提交：

```text
213a4dc856b06819964511bdcd94e57db62e0913
```

官方代码默认在 `main.py` 中使用：

```text
PFClient
```

源码本身同时包含 `Nav2Client`，但默认被注释。

## 二、本项目正式运动后端

为了使 AIMAPP 与 SCA-AIFNav baseline 在配对实验中使用相同的低层运动执行后端，
正式实验统一采用 Nav2。

因此 AIMAPP 相对于官方代码仅修改：

```text
self.motion_client = PFClient()
```

为：

```text
self.motion_client = Nav2Client()
```

除运动后端选择外，不修改 AIMAPP 的：

- 主动推断模型；
- Expected Free Energy；
- MCTS；
- 观测模型；
- 状态空间；
- 认知地图；
- action space；
- 节点影响半径；
- panorama 参数；
- 在线学习逻辑。

## 三、曾显示为 modified 的三个文件

此前以下文件曾在 Git 状态中显示修改：

```text
aimapp/aimapp/motion/align_odom_to_belief.py
aimapp/aimapp/motion/potential_field_action.py
aimapp/aimapp/obs_transf/get_pano_multiple_camera_action.py
```

通过 Git blob hash 比较确认，这三个文件的实际内容与官方 `213a4dc`
完全一致，仅存在工作区文件元数据差异。

现已全部恢复至官方状态。

## 四、main.py 文件权限

此前 `main.py` 还存在：

```text
100644 -> 100755
```

的非必要权限变化。

正式冻结前已恢复为官方的：

```text
100644
```

因此最终 patch 不包含文件权限变化。

## 五、本地 AIMAPP Nav2 基线

本地 reproduction 分支正式冻结 commit：

```text
20746e05ab87ec8a63c969a81c99213704769183
```

其直接基础为：

```text
213a4dc856b06819964511bdcd94e57db62e0913
```

最终定义：

> **AIMAPP baseline = 官方 AIMAPP 213a4dc + 仅将运动后端选择从 PFClient 切换为 Nav2Client。**

## 六、可复现 patch

唯一源码差异保存于：

```text
docs/audit/AIMAPP_NAV2_BASELINE_2026-09-11.patch
```

正式实验记录应同时保存：

- AIMAPP 官方基础 commit；
- AIMAPP Nav2 baseline commit；
- SCA-AIFNav commit；
- experiment harness commit；
- 各 runtime source fingerprint。
