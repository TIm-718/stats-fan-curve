# Stats Fan Curve

基于 [exelban/stats](https://github.com/exelban/stats) 的个人改造版，为带风扇的 Apple Silicon Mac 增加**基础转速保持**和**温度自动风扇曲线**，继续使用 Stats 原有菜单栏界面。

改造与维护：**Evan 梓豪 / Evan Lin**。这是独立改造项目，和 Stats、MacFanPro 官方发行版分别维护。原应用的监控功能与代码归其原作者及贡献者所有；本项目重点是风扇规则与集成。

## 增加了什么

- 每个风扇可设置基础转速与最高转速。
- 基础保持、温度曲线独立开关，也可同时启用。
- 在两个温度阈值之间线性提速，带持续升温判定、回落滞后和升降速限制。
- 温度失效时交还系统；正常退出或暂停时恢复系统控制。
- CPU/GPU 达到 95 °C 时使用硬件最高转速，低于 90 °C 解除保护。
- 保存设置，重新打开或唤醒后按规则恢复。
- Stats 调用内嵌 MacFanPro 控制组件执行风扇写入，日常只需打开 Stats。

规则详情：[TEMPERATURE-FAN-CURVE.md](TEMPERATURE-FAN-CURVE.md)。主要代码与发布整理：[改造说明](docs/CHANGES.md)。

## 当前版本与范围

已有本地包为 **Stats 3.0.23 / 自定义构建 851.3，Apple Silicon 实验版本**。

- 内嵌控制组件要求 macOS 14 或更新版本。
- 历史实机记录来自 macOS 15.3.1 的单风扇 Apple Silicon Mac，其他设备与系统组合尚未逐项验证。
- Stats 主程序含多架构，但改造框架和控制组件针对 Apple Silicon；本包不作为 Intel 版本发布。
- 安装包是本地签名，**没有 Apple Developer ID 公证**，macOS 可能阻止首次打开。请检查来源和文件；无需为本项目关闭系统整体安全保护。
- 无风扇机型没有风扇调速功能；转速受实际硬件范围限制。
- 应用仍叫 Stats，与同名原版共享配置域，安装前应退出原版并保留需要的备份。

## 下载与使用

第一版安装包放在本仓库 **Releases**，源码不提交应用包或编译缓存。Stats 官方下载和 Homebrew 安装得到的是原版，不含本项目的改造。

1. 下载并解压本仓库的 Apple Silicon 安装包。
2. 退出已有 Stats，按自己的安装方式将 Stats.app 放入应用程序目录。
3. 打开 Stats → 设置 → 传感器，填写基础和最高转速，按回车或离开输入框保存。
4. 根据需要开启基础保持、温度曲线或两者。
5. 首次写入风扇转速需系统管理员授权安装后台组件，无需单独使用 MacFanPro 界面。

规则示例：基础 2200 RPM、最高 4000 RPM、开始提速 55 °C、到顶 70 °C。两项开关同时打开时，低温保持基础转速，持续升温后逐渐加速。这是功能示例，不是对所有 Mac 的推荐配置。

**使用本改造项目的包升级。** 官方更新可能覆盖改造功能，可在 Stats 通用设置中把官方检查更新设为“从不”。

## 测试与构建

纯规则测试仅需 macOS 的命令行开发工具：

```bash
bash scripts/test-fan-rules.sh
```

Apple Silicon 本地框架与模拟控制器：

```bash
bash scripts/build-kit-local.sh
bash scripts/test-fan-controller.sh
bash scripts/build-sensors-local.sh
```

控制器测试用记录桥接，不安装服务、不写真实风扇；只使用并清理自己的测试偏好域。

上述脚本构建 Kit/Sensors 和测试，**不是完整应用的一键打包流程**。完整应用仍需要 Stats Xcode 工程、风扇组件和最终打包，见 [构建范围](docs/BUILDING.md)。

本次从清理后的源码重新执行：**113 项规则、11 项控制器检查通过，Kit 与 Sensors 编译通过**。未在本次重跑完整应用构建或实机调速。详见 [验证说明](docs/VALIDATION.md)。

## 来源与许可

- [Stats](https://github.com/exelban/stats)：基础应用，保留原 MIT 许可，见 [LICENSE](LICENSE)。
- [MacFanPro](https://github.com/macfanpro/macfanpro)：规则参考、控制组件与安装流程，见 [References](References/README.md)。
- MacFanPro 源自 [ThermalForge](https://github.com/ProducerGuy/ThermalForge)，来源记录及 MIT 许可随源码保留。
- LevelDB、Snappy、Swift Argument Parser 等许可索引见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

原始 Stats README 归档在 [docs/UPSTREAM-README.md](docs/UPSTREAM-README.md)，其中的原版下载与支持说明不代表本改造版。

本地目录没有原 Git 历史，不伪造精确基础提交；源码中的 Stats 版本号为 3.0.23。报告问题请附本包构建号、Mac 型号、macOS 版本和复现步骤。

