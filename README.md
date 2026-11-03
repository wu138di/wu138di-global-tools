# wu138di 全球上网 V1.0

## v1.0.1 update

- 修复 U30 Pro B24 拉取安装资源失败：核心、面板与规则改用阿里云 HTTPS 下载，保留 SHA256 校验。
- 修复 F50 **未预装 BusyBox** 时的环境安装与工具路径适配；仍需要 Root，**不是免 Root 版**。
- 修复出口网卡写死、节点域名引导解析、全局模式的节点检查与换行兼容；不再显示按等待次数推算的百分比。

| 机型 | TXT | JS | 本次验证状态 |
| --- | --- | --- | --- |
| U30 Pro / MU5358 B24 | [下载](dist/wu138di-global-tools-u30-v1.0.1.txt) | [下载](dist/wu138di-global-tools-u30-v1.0.1.js) | 已完成实机节点、HTTPS、电脑透明代理与关闭恢复测试 |
| F50 / MU300 B08 | [下载](dist/wu138di-global-tools-f50-v1.0.1.txt) | [下载](dist/wu138di-global-tools-f50-v1.0.1.js) | 候选适配包；本地回归通过，尚未完成同等实机测试 |

[GitHub 发布包](https://github.com/wu138di/wu138di-global-tools/releases/tag/v1.0.1) · [阿里云下载](https://8.134.248.110/global-tools/plugins/v1.0.1/wu138di-global-tools-v1.0.1.zip)（U30/F50 分包）

JS/TXT 二选一，只导入对应机型的界面插件。不要把 F50 包装到 U30；安装不是刷机，不清空订阅。初始口令 **2007**，可在设置更改。透明代理与开机自启需手动开启。

源码构建全部变体：`python scripts/build-all.py`。U30 测试：`npm ci && npm test`；F50 测试：在 `variants/f50` 目录执行相同命令。机型专用源码分别为 `src/` 和 `variants/f50/src/`。



面向 **UFI-TOOLS** 的 Mihomo 代理配置插件。支持订阅、节点 YAML、规则查看、连接管理、测速与网络检测哦~₍ᐢ.ˬ.ᐢ₎♡~。

<img width="1199" height="676" alt="3-2" src="https://github.com/user-attachments/assets/e110b84a-ffda-458b-94e7-9f922f1860dc" />

## 功能

- 概览、节点、订阅、规则、连接、检测、设置。
- HTTPS 订阅和 YAML 文件/文本导入；YAML 需包含标准 `proxies:` 节点段。
- 导入只更新节点，不覆盖网关 DNS、端口、规则与运行模式；先校验、再提交，失败恢复原数据。
- 本地 YAML 模式暂停定时订阅刷新，重新导入链接后恢复订阅模式。
- 使用节点所属 provider 的健康检查接口；测速和设备命令串行，显示核心返回的测量值。过期历史值不当作当前延迟。
- 开启前检测节点与本机代理 HTTPS 链路；节点不可用时不接管终端流量。
- 网络检测区分路由、DNS、国内直连、代理连接；订阅 HTTP 401/403 单独显示。
- 内置 SVG 国旗与独立选中标记，无外部旗标 CDN。
- 樱花背景、玻璃卡片、手机底栏、桌面侧栏、系统深浅色跟随和 44px 触控区域。

安装界面不代表开启代理；使用电源按钮手动开启/停止，开机自启独立控制。关闭网页不等于停止设备代理。

## 适用范围

当前 U30 Pro / MU5358 B24 已完成本次实机验证；F50 B08 仍按候选包发布，未完成本次实机验收。安装器依赖 Android ARM64、Root、Magisk BusyBox、系统 curl、`br0`、`sipa_eth0`、`192.168.0.1/24` 及相应透明代理内核能力。

节点测速、订阅可用性与平台播放权限是不同事项；延迟数值随节点和网络变化，不承诺所有节点低于某个固定数值。

其余支持UFI-TOOLS的有待测试，欢迎来联系我测试！

## 源码构建与测试

需要 Python 3.10+、Node.js 20+ 和 npm。

```sh
npm ci
npm test
python scripts/build.py
```

`dist/` 为可直接导入的独立文件；运行时不依赖 npm、Python、外部 JS CDN。测试使用合成数据，不访问用户设备。
## 声明

本仓库不是 UFI-TOOLS、Mihomo 或 Clash 的官方发行版。界面布局参考 Clash Verge，未包含其桌面程序。代码许可不自动涵盖图片素材的第三方权利。

## 支持我

制作实属不易，如果你想为爱发电，可以扫下面的码支持我~谢谢啦

<img width="1382" height="1382" alt="mm_reward_qrcode_1792512034770" src="https://github.com/user-attachments/assets/b684be82-806f-4a94-9248-ec0028d21167" />


**Made by wu138di**
