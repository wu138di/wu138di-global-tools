# 组件与署名

- **wu138di 自研管理引擎**：本项目的 Go 管理服务、HTTP 兼容工具、网页交互与 ADB 自动化。HTTP 工具只实现设备脚本所需的固定选项，不是 curl 的完整实现。
- **Mihomo v1.19.32**：代理内核，GPL-3.0；[源代码](https://github.com/MetaCubeX/mihomo/tree/v1.19.32)。不宣称该内核为本项目原创。
- **MetaCubeXD v1.270.6**：内核附带面板资源；[源代码](https://github.com/MetaCubeX/metacubexd/tree/v1.270.6)。
- **BusyBox**：原样取自 Magisk v30.7 ARM64 APK；GPL，许可证在 `vendor/busybox/`。对应代码与构建信息：[Magisk v30.7](https://github.com/topjohnwu/Magisk/tree/v30.7)，递归获取其子模块。
- **Magisk v30.7 APK**：官方未修改文件，SHA256 固定，作为可选 Root 准备工具随包提供；许可证随包保留。不代表已经为任何机型完成 Root。
- **Android Platform-Tools**：由安装器按用户选择从 [Google 官方](https://developer.android.com/tools/releases/platform-tools) 获取，不在本项目安装包中重新分发 SDK 二进制；用户需接受相应许可。
- 规则数据来自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)。
- 界面图像由项目作者提供，代码许可不自动涵盖图片的第三方权利。

旧版界面插件与其 SDK 已从当前源码和发布入口移除。保留必要的旧路径迁移逻辑，仅用于兼容设备上已有配置，不需要旧平台运行。
