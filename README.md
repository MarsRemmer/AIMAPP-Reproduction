# AIFNav Experiment Harness

该仓库负责 AIMAPP 与 SCA-AIFNav 的统一实验运行、记录和评价。

本地位置：

```text
~/SCA-AIFNav-Project/experiments
```

实验结果统一写入：

```text
~/SCA-AIFNav-Project/results
```

算法本体分别位于：

```text
~/SCA-AIFNav-Project/aimapp
~/SCA-AIFNav-Project/sca_aifnav
```

当前正式基线协议：

- AIMAPP + Nav2；
- SCA-AIFNav baseline + Nav2；
- 相同环境并尽量使用相同起点；
- 每次 200 个完成的高层动作；
- coverage 只作为评价指标；
- 失败 trial 保留并记录；
- 每个环境至少获得 5 个成功 paired runs。
