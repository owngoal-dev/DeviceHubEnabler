# DeviceHubEnabler

[English](README.md) | [简体中文](README-zh-CN.md)

custom firmware を導入した **iOS 17.0–26.x** デバイスで、Xcode の DeviceHub から **View Screen**（画面のライブ表示）と**システム音声の出力**を可能にします。Info や Settings は DeviceHub の標準機能をそのまま使います。

[yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler)（MIT）を Theos ではなく [Apelin](https://github.com/owngoal-dev/Apelin) で書き直したもので、**rootless**（arm64・arm64e）と **roothide**（arm64e）の両方のパッケージを提供します。設計は [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli) の DeviceHubFix の研究に基づきます。

## 仕組み

DeviceHub は Developer Disk Image（DDI）内の `dtremotedisplayd` を介して画面を表示します。ストリーム開始前にデバイスが対応するメディアストリーム機能を尋ね、回答が空でなくなるまで何度も繰り返します。量産デバイスでは DDI の `CoreDeviceUtilities` がポリシーにより 0 を返すため、表示はずっと読み込み中のままになります。この Tweak は `dtremotedisplayd` にのみ注入され、iOS 17–26 で次の 2 つの getter を置き換えます。

- `MediaStreamSupportedFeatures.current` → `0x8c`（プライマリ画面のミラー映像 `0x04` | システム音声 `0x08` | ディスプレイ情報 `0x80`）。値は DDI 自身の `init(rawValue:)` で構築します。
- `CurrentDevice.isCustomerRestricted` → `false`。

3 つの Swift シンボルはマングル名で探し、1 つでも見つからなければ何もフックせず、システムの既定の動作を保ちます。

## 要件

| | |
| --- | --- |
| iOS | 17.0 – 26.x（それ未満は従来の `DeveloperDiskImage` 経路で Xcode 27 は非対応。27 以降はデバイス自身が機能を報告） |
| custom firmware | rootless または roothide。`mobilesubstrate`（ElleKit）が必要 |
| Xcode | 27.x（DeviceHub 含む） |

## インストール

ブートストラップに合う `.deb`（rootless は `iphoneos-arm64`、roothide は `iphoneos-arm64e`）をインストールします。respring は不要です。インストール時に `dtremotedisplayd` が動いていれば postinst が再起動して Tweak を読み込みます。動いていなければ何もせず、次に Mac を接続したときに CoreDevice が Tweak 込みで起動します。

## 確認

1. デバイスを接続し、Mac を信頼して開発者モードを有効にします。
2. **Xcode ▸ Window ▸ Devices and Simulators**（または DeviceHub）を開き、ペアリングを待ちます。
3. デバイスを選んで **View Screen** を押すと、ライブ画面とシステム音声が表示されます。

まだ読み込み中のままの場合は、Mac のコンソールでプロセス DeviceHub の `supportedFeatures: 140` を、デバイス側ではサブシステム `wiki.qaq.devicehubenabler` の `Hooks installed` を確認してください。`Scripts/check-ddi.sh` は Mac 上で DDI の `CoreDeviceUtilities` に 3 つのシンボルがあるか調べます。

## アンインストール

パッケージを削除します。`dtremotedisplayd` が動いていれば `launchctl kickstart -k user/501/com.apple.coredevice.dtremotedisplayd` を実行します。

## クレジットとライセンス

- [yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler) の書き直し。MIT License、Copyright © 2026 yyyywaiwai。
- 設計は [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli) の [DeviceHubFix の研究](https://lakr233.github.io/vphone-cli/research/Guest/devicehub_screen_viewing.html) に基づきます。
- MIT ライセンス。[LICENSE](LICENSE) を参照してください。
