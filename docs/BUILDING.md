# 构建范围

## 已验证的框架与测试

需要 Apple Silicon macOS 和 Xcode Command Line Tools，产物写在仓库内 .build-local/。

```bash
bash scripts/test-fan-rules.sh
bash scripts/build-kit-local.sh
bash scripts/test-fan-controller.sh
bash scripts/build-sensors-local.sh
```

Kit 从 Kit/lldb/lldb.m 编译 Objective-C++ 对象，链接随上游保留的多架构 libleveldb.a；Sensors 从 reader.m 编译 Objective-C 对象。当前本地脚本以 arm64 为目标。模拟控制器不调用真实风扇。

## 完整应用

保留了 Stats Xcode 工程，但本次没有完整 Xcode，只重新编译两个改造框架与测试，不等同完整应用打包验证。

自定义曲线还要求 Stats 应用中包含 Contents/Helpers/MacFanPro.app 及 CLI、安装资源、第三方许可。仅编译 Stats 工程不会由本地框架脚本自动补齐这些组件。组件的源码和自身构建说明见 References/MacFanPro/。

已有 851.3 包是在开发机已有应用模板基础上替换框架、嵌入控制组件并本地签名得到的。完整应用一键构建与 CI 发行尚未完成，后续再补。

原版 Makefile 与 docs/upstream-github 中的发布流程包含原维护者签名/更新配置，不应直接当作本改造版发布命令。

## 硬件

常规测试不安装控制服务、不写真实风扇。实机温度、睡眠/唤醒和调速需单独安排，本次没有执行。

