# DeviceHubEnabler

[简体中文](README-zh-CN.md) | [日本語](README-ja.md)

Enables **View Screen** (live screen viewing) and **system audio output** in Xcode's DeviceHub on **iOS 17.0–26.x** devices running custom firmware. Info and Settings keep using DeviceHub's built-in features.

A rewrite of [yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler) (MIT) built with [Apelin](https://github.com/owngoal-dev/Apelin) instead of Theos, packaged for both **rootless** (arm64, arm64e) and **roothide** (arm64e). The design comes from the DeviceHubFix research in [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli).

## How it works

DeviceHub views a device through `dtremotedisplayd` in the Developer Disk Image (DDI) and keeps asking it which media stream features the device has until the answer is non-empty. On a production device the DDI's `CoreDeviceUtilities` answers 0 by policy, so the view spins forever. The tweak injects only into `dtremotedisplayd` and, on iOS 17–26, replaces two getters there:

- `MediaStreamSupportedFeatures.current` → `0x8c` (primary mirrored video `0x04` | system audio `0x08` | display information `0x80`), built through the DDI's own `init(rawValue:)`.
- `CurrentDevice.isCustomerRestricted` → `false`.

The three Swift symbols are looked up by their mangled names; if any is missing, nothing is hooked and the system keeps its default behaviour.

## Requirements

| | |
| --- | --- |
| iOS | 17.0 – 26.x (older: legacy `DeveloperDiskImage` path, not supported by Xcode 27; 27+: reports the features itself) |
| Custom firmware | rootless or roothide with `mobilesubstrate` (ElleKit) |
| Xcode | 27.x with DeviceHub |
| Verified | iPhone16,1 (iPhone 15 Pro Max) on iOS 17.3.1, roothide, Xcode 27: View Screen picture and system audio |

## Install

Install the `.deb` for your bootstrap (`iphoneos-arm64` for rootless, `iphoneos-arm64e` for roothide) from the [releases](https://github.com/owngoal-dev/DeviceHubEnabler/releases) or the OwnGoal source `https://apt.owngoal.dev/`. No respring is needed. If `dtremotedisplayd` is running, the postinst restarts it so the tweak is picked up; if not, CoreDevice starts it with the tweak the next time a Mac connects.

## Verify

1. Connect the device, trust the Mac and enable Developer Mode.
2. Open **Xcode ▸ Window ▸ Devices and Simulators** (or DeviceHub) and wait for pairing.
3. Select the device and click **View Screen**: the live screen and system audio should appear.

If it still spins, check the Mac's Console (process DeviceHub) for `supportedFeatures: 140`, and the device log subsystem `wiki.qaq.devicehubenabler` for `Hooks installed`. `Scripts/check-ddi.sh` checks a DDI's `CoreDeviceUtilities` for the three symbols on the Mac.

## Uninstall

Remove the package; if `dtremotedisplayd` is running, run `launchctl kickstart -k user/501/com.apple.coredevice.dtremotedisplayd`.

## Credits & License

- Rewrite of [yyyywaiwai/DeviceHubEnabler](https://github.com/yyyywaiwai/DeviceHubEnabler), MIT License, Copyright © 2026 yyyywaiwai.
- Design based on the [DeviceHubFix research](https://lakr233.github.io/vphone-cli/research/Guest/devicehub_screen_viewing.html) in [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli).
- MIT License, see [LICENSE](LICENSE).
