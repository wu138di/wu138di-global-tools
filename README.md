# wu138di 全球上网 V1.0

面向 **UFI-TOOLS** 的 Mihomo 代理配置插件。支持订阅、节点 YAML、规则查看、连接管理、测速与网络检测哦~₍ᐢ.ˬ.ᐢ₎♡~。

首页图

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

当前仅在 **ZTE U30 Pro / F50** 环境实测。安装器依赖 Android ARM64、Root、Magisk BusyBox、系统 curl、`br0`、`sipa_eth0`、`192.168.0.1/24` 及相应透明代理内核能力。

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
