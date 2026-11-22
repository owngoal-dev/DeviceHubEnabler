# DeviceHubEnabler

[English](README.md) | [日本語](README-ja.md)

让运行 custom firmware 的 **iOS 17.0–26.x** 设备在 Xcode 的 DeviceHub 里可以 **View Screen**（实时画面）并输出**系统音频**。Info、Settings 等面板照旧使用 DeviceHub 自带功能。

重写自 [yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler)（MIT），用 [Apelin](https://github.com/owngoal-dev/Apelin) 构建而非 Theos，同时提供 **rootless**（arm64、arm64e）和 **roothide**（arm64e）两种包。设计来自 [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli) 的 DeviceHubFix 研究。

## 原理

DeviceHub 通过开发者磁盘镜像（DDI）里的 `dtremotedisplayd` 查看屏幕，开始前会反复询问设备支持哪些媒体流特性，直到答案非空。量产设备上 DDI 的 `CoreDeviceUtilities` 按策略返回 0，于是画面一直转圈。插件只注入 `dtremotedisplayd`，在 iOS 17–26 上替换其中两个 getter：

- `MediaStreamSupportedFeatures.current` → `0x8c`（主显示镜像视频 `0x04` | 系统音频 `0x08` | 显示信息 `0x80`），通过 DDI 自己的 `init(rawValue:)` 构造。
- `CurrentDevice.isCustomerRestricted` → `false`。

三个 Swift 符号按修饰名查找；任一缺失就不装钩子，系统保持默认行为。

## 要求

| | |
| --- | --- |
| iOS | 17.0 – 26.x（更低版本走旧 `DeveloperDiskImage` 通道，Xcode 27 不支持；27 起设备自己会报告特性） |
| custom firmware | rootless 或 roothide，需 `mobilesubstrate`（ElleKit） |
| Xcode | 27.x（含 DeviceHub） |

## 安装

按引导安装对应的 `.deb`（rootless 为 `iphoneos-arm64`，roothide 为 `iphoneos-arm64e`），不需要 respring。安装时 `dtremotedisplayd` 若正在运行，postinst 会重启它以加载插件；没在运行则不动，下次 Mac 连接时由 CoreDevice 带插件拉起。

## 验证

1. 连接设备，信任此 Mac 并开启开发者模式。
2. 打开 **Xcode ▸ Window ▸ Devices and Simulators**（或 DeviceHub），等待配对完成。
3. 选中设备，点 **View Screen**：应出现实时画面和系统声音。

如果仍然转圈：在 Mac 的「控制台」里看进程 DeviceHub 是否输出 `supportedFeatures: 140`，在设备上看 `wiki.qaq.devicehubenabler` 子系统日志是否有 `Hooks installed`。`Scripts/check-ddi.sh` 可在 Mac 上检查 DDI 的 `CoreDeviceUtilities` 是否含这三个符号。

## 卸载

移除包；若 `dtremotedisplayd` 正在运行，执行 `launchctl kickstart -k user/501/com.apple.coredevice.dtremotedisplayd`。

## 致谢与许可

- 重写自 [yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler)，MIT License，Copyright © 2026 yyyywaiwai。
- 设计基于 [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli) 的 [DeviceHubFix 研究](https://lakr233.github.io/vphone-cli/research/Guest/devicehub_screen_viewing.html)。
- MIT 许可，见 [LICENSE](LICENSE)。
