# 改造范围

本目录没有原 Git 历史，不声称已按某个精确上游提交生成完整差异。这里列出已识别的主要改造，不把原 Stats 监控功能算作新增。

## 已有功能

- Modules/Sensors/fanCurveDemand.swift：基础保持、曲线需求、滞后和过热分支。
- Modules/Sensors/fanCurve.swift：配置保存、限幅、控制权交接与回调代次。
- Modules/Sensors/macFanProBridge.swift：内嵌 CLI、一次性管理员安装与临时安装副本回收。
- Sensors 设置及读数/启停接入、相关英中文案和工程文件。
- Kit/helpers.swift 等已有改动：相关系统查询的有界等待，避免无响应磁盘无限阻塞。
- 规则与控制器模拟测试，以及此前的本地实机记录。

## 2026-11-03 发布整理

- 编写改造版 README，原始 Stats README 保存在 docs/UPSTREAM-README.md。
- 排除 1.2 GB 本地缓存、临时对象、应用目录与旧安装包。
- 保留原许可证、来源及第三方声明。
- 修正 References 的旧描述，使其符合当前 MacFanPro 写入路径。
- Kit/Sensors 脚本补上 Objective-C/Objective-C++ 源码对象编译，消除对既有对象缓存的依赖。
- 控制器测试改用本地新编译框架，去掉对已有 Stats.app 的依赖，并在退出时清理测试偏好域。
- 上游签名和自动发布工作流归档在 docs/upstream-github，不冒称本仓库已有发行自动化。

本次未更改风扇控制规则或真实硬件设置。

