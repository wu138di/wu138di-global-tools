# wu138di 全球上网

**自研管理引擎 · ADB 独立部署 · 浏览器管理**

无需配套平台或专用 App。管理服务、原生 HTTP 工具、界面与安装自动化由本项目提供；**代理内核为 Mihomo**，第三方组件保留原署名与许可证。

## 下载与安装

从 [GitHub Release](https://github.com/wu138di/wu138di-global-tools/releases/tag/v1.1.0-alpha.2) 或 [阿里云镜像](https://8.134.248.110/global-tools/plugins/standalone/v1.1.0-alpha.2/wu138di-global-tools-v1.1.0-alpha.2-windows.zip) 下载 **v1.1.0-alpha.2 Windows 安装包**，解压后双击 `setup.cmd`。

1. USB 连接设备并开启 USB 调试，或连接设备 Wi-Fi 并使用已开启的无线 ADB。
2. 安装器自动识别 ADB、单台已授权设备、机型、固件和 Root，部署独立管理端。
3. 浏览器打开 **https://192.168.0.1:9088/**。初始口令 **2007**，可在设置更改。

首次访问使用设备自签名证书，需要自行确认。网页只监听设备局域网，不开放蜂窝公网。原有代理和自启状态保留；安装不主动开启代理。

### ADB 与 Root 环境

- 优先复用现有 ADB/Android SDK。缺少 ADB 时，经用户接受 Android SDK 许可后从 Google 下载锁定版本，校验 SHA256；不改系统 PATH、不安装驱动、不替用户确认调试授权。
- 包内包含 BusyBox、原生 HTTP 工具、离线内核/规则/面板资源，以及官方 **Magisk v30.7 APK**。新环境不借用旧平台的 curl。
- 已有 Root：保留当前 Magisk/Root 框架，不强制升级；检查并准备受支持的启动脚本目录。
- 尚无 Root：准备 Magisk 应用和设备报告后停止。**安装 APK 不等于完成 Root**。首次刷写仍需本机当前固件、正确分区与 Bootloader 条件；安装器不执行解锁、刷分区、擦除或重启。遵循 [Magisk 官方安装说明](https://topjohnwu.github.io/Magisk/install.html)，不要使用他人的修补镜像。

`check-env.cmd`：检查环境。`prepare-root.cmd`：准备 Root 所需应用与设备报告。报告位于本地 `reports/`，不上传。

高级用法：

```powershell
.\bootstrap.ps1 -Action Install -Device 192.168.0.1:5555 -Adb C:\Android\platform-tools\adb.exe
.\bootstrap.ps1 -Action Check
.\bootstrap.ps1 -Action PrepareRoot
```

无线调试只在受信局域网显式开启：`-Action ConnectWifi -Device USB_SERIAL -WifiIp 192.168.0.1 -EnableWirelessAdb`。恢复 USB 模式用 `adb -s DEVICE usb`。

## 功能

订阅/YAML 导入、节点与地区国旗、真实测速、地区分流、规则与连接查看、网络检测、核心启停、代理自启、口令修改。停止核心后仍显示已保存节点，不伪造当前延迟或流量。

设备直连订阅失败时，可尝试通过现有可用节点下载，保留 TLS 校验，不自动开启透明代理。全新无节点时可导入 YAML。此回退来源支持“立即更新”，尚未实现独立管理端定时刷新。

## 兼容状态

| 设备 | 状态 |
|---|---|
| U30 Pro / MU5358 B24 | 独立端已有实机验证；新安装器与工具验证记录见本版 Release |
| F50 / MU300 B08 | 独立候选适配，控制端口 19090，保留原厂 9090；尚未完成同等实机验收 |
| 其他 CPE / 固件 | 不默认通刷，安装前按机型与构建号检查 |

仍需 Android ARM64、Root、内核网络能力及设备局域网条件。节点延迟、服务端可用性与平台地区解锁不同，不保证每个节点低于 500ms。

## 启停与回滚

管理端自启与代理自启分开。Root 终端：`/system/bin/sh /data/adb/wu-global/manager.sh start|stop|status|boot-on|boot-off`（一次一个动作）。初次安装不创建管理端自启，设备重启后可手动启动。

安装输出设备专属 `rollback.sh` 路径。脚本归档新目录、恢复旧管理端，不删除节点或用户配置。旧运行脚本的工具迁移另有备份与回滚，须关闭透明代理后执行。共享工具保留，以免破坏已安装核心。

## 源码

`standalone/`：Go 管理引擎、原生 HTTP 工具、网页与测试。`device/`：独立设备控制与离线安装脚本。`installer/`：ADB/Root 准备器。`vendor/`：第三方工具与许可证。

构建需要 Go 1.26、Python 3、Node.js 20+：`npm ci`，`python standalone/build.py --host`，`npm test`。依赖资源按 SHA256 校验，发布包内已携带设备端所需资源。

本仓库不包含个人订阅、节点凭据、API 密钥或设备备份。参见 [组件说明](NOTICE.md)。

**Made by wu138di**
