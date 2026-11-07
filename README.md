<p align="center">
  <img src="icon-preview-256.png" width="120" height="120" alt="SoundMirror icon">
</p>

<h1 align="center">SoundMirror</h1>

<p align="center">
  无线投屏工具：可选<b>只投音频</b>，或<b>音频与画面一起投</b>到电脑 —— 走 Wi-Fi 或 USB，<b>完全不占用蓝牙</b>。
</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Version" src="https://img.shields.io/badge/version-0.2.3-blue">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE">
</p>

---

A wireless casting tool for Windows: stream your phone's **audio only**, or **audio together with the screen**, to your PC over Wi-Fi or USB — without touching Bluetooth. Chinese UI, single-file script, no installation.

## 为什么做这个

市面上的方案要么只能投屏、要么只能传声音，要么得占用蓝牙（然后你就没法同时用蓝牙耳机了）。SoundMirror 的做法是把两件事合成一个开关：

- **只要声音** → 勾掉画面，纯音频转发，延迟低、音质无损
- **声音 + 画面** → 勾上，手机屏幕和声音一起过来

底层用的就是 scrcpy 的音频转发能力，所以不需要在手机上安装任何 App，也不经过应用商店的安装校验（华为等开启纯净模式的机型尤其受用）。

## 特性

| | |
|---|---|
| **双通道** | 音频单独转发，或音频 + 屏幕镜像，一个勾选框切换 |
| **两种连接** | Wi-Fi（免线，`adb tcpip`）或 USB（最稳，延迟恒定） |
| **手机零安装** | 只往 `/data/local/tmp` 推一个 server，不装 App、不触发纯净模式 |
| **蓝牙保持空闲** | 音频走 USB / Wi-Fi，蓝牙耳机照常用于电脑 |
| **失败有话说** | 连不上时不用猜——界面直接给出下一步排查方向，日志窗口可看原始输出 |
| **图形界面** | 输入 IP → 点开始，不用记命令行参数 |
| **手机熄屏** | 转发过程中一键关掉手机面板，画面照常传输、不断流 |
| **后台常驻** | 关窗口或最小化即收进托盘，转发不中断；托盘菜单可直接启停 |
| **原生 exe** | 可编译成无控制台窗口的 exe，图标、版本信息齐全 |

## 界面

<p align="center">
  <img src="screenshot.png" width="422" alt="SoundMirror 主界面">
</p>

- 圆点是状态：灰=空闲，橙=连接中，绿=转发中，红=失败
- 选「USB 数据线」时 IP 输入框自动禁用变灰，不需要填
- 转发中同一个按钮变成「停止转发」
- 右上角「日志」看 scrcpy 原始输出，连不上时先看它
- 右侧「手机熄屏」只关手机面板，镜像照常；点亮请按手机电源键（见下方说明）
- 点关闭或最小化都会收进托盘，转发继续；要退出请右键托盘图标选「退出」

## 环境要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）
- 手机：Android 11+（对应 `ro.build.version.sdk` ≥ 30）。HarmonyOS 4.x 的兼容层是 API 31，可用
- 手机上开启「USB 调试」

## 快速开始

### 1. 获取 scrcpy 运行文件

仓库不含 scrcpy 二进制（约 26 MB）。执行一次自动下载：

```powershell
.\Setup-Scrcpy.ps1
```

脚本会下载官方 scrcpy v5.0.1，与官方 `SHA256SUMS.txt` 比对哈希后解压到 `scrcpy\scrcpy-win64-v5.0.1\`。国内网络默认走镜像加速。

### 2. 手机端准备

1. 设置 → 关于手机 → 连点「版本号」7 次，开启开发者选项
2. 系统和更新 → 开发人员选项 → 打开 **USB 调试**
3. 同一页面打开 **「仅充电」模式下允许 ADB 调试**
4. 华为 / HarmonyOS 额外注意：还有一个独立的 **「ADB 调试（安全设置）」** 开关，默认关闭。不打开的话，即使开了 USB 调试也连不上——这是最容易漏的一步

### 3. 建立连接

**USB 模式**：插上线，手机通知栏把 USB 模式切成「传输文件」，界面里选「USB 数据线」即可。

**Wi-Fi 模式**：第一次仍需插一次线，把 adb 切到 TCP：

```bat
cd scrcpy\scrcpy-win64-v5.0.1
adb devices
adb tcpip 5555
adb connect 192.168.1.50:5555    :: 换成手机 WLAN 里显示的 IP
```

看到 `connected to 192.168.1.50:5555` 就可以拔线了。之后界面里填这个 IP，选 Wi-Fi，点开始。

> 手机重启或电脑的 adb 服务重启后，5555 端口会失效，需要重新插线跑一次 `adb tcpip 5555`。

### 4. 启动

```bat
SoundMirror.bat
```

或双击编译好的 `SoundMirror.exe`。

## 编译成 exe（可选）

仓库不带 exe。编译脚本用系统自带的 .NET Framework 编译器，无需安装任何工具：

```bat
Build-EXE.bat
```

产物是 `SoundMirror.exe`（约 15 KB，原生 Windows 程序），图标和版本信息已经嵌好。

这个 exe 是一个**启动器**：它用 `CreateNoWindow` 起 PowerShell 去跑 `sound-mirror.ps1`，所以没有黑框闪烁，任务管理器里也能看到 `SoundMirror.exe` 这个进程。

`SoundMirror.bat` 保留作为备用入口——万一 PowerShell 执行策略或杀软拦了 exe，双击 bat 通常还能起来。

## 常见问题

**连不上，界面提示「连接失败」**

按顺序查：手机 IP 是否变了（Wi-Fi 里看）、电脑和手机是否同一网段、路由器是否开了 AP 隔离、手机是否重启过导致 `adb tcpip` 失效。

**能连上但没声音**

声音走的是 **Windows 默认播放设备**。先确认它是你想出声的那个（蓝牙耳机 / 音箱），再检查手机音量。如果手机音量是 0，转过去也是静音。

**某些 App 的音频转不出来**

带 DRM 保护的应用（部分视频、音乐客户端）会禁止系统采集音频，转出来是静音。这是系统级限制，没有绕过办法。

**想同时用蓝牙耳机**

完全没问题。这个工具不碰蓝牙——音频走 USB 或 Wi-Fi，蓝牙完整留给耳机。

**Wi-Fi 下延迟越来越大**

scrcpy 有音频缓冲管理，一般比老的 sndcpy 稳很多。若长时间播放后出现累积延迟，点「停止转发」再「开始转发」重启一次链路。

**点了「手机熄屏」，怎么点亮？**

按一下手机电源键即可。熄屏走的是 SurfaceFlinger 的显示电源开关，**设备并没有真正休眠**，所以按一下就回到原来的界面，不用重新连接。

程序不提供「点亮」按钮，是因为在部分机型（实测华为 HarmonyOS）上，scrcpy 的 `MOD+Shift+o` 只能把 SurfaceFlinger 的电源恢复成 On、亮度读数也正常，但面板背光不会回来；唯一能点亮的是走一次系统电源周期，而那必然落到锁屏、要解锁一次——代价比按一下电源键大得多，所以没有做。

**关窗口后程序去哪了？**

收进了右下角通知区域。双击图标恢复界面，右键可以启停转发或退出。首次可能被放在 `^` 溢出区里，拖出来一次即可常显。

## 更新日志

### v0.2.3

- 修复：转发一段时间后电脑端画面停住（手机自动锁屏导致采集断帧）。现在转发期间保持手机常亮，停止时按原值恢复
- 修复：读屏幕状态、下发 adb 设置的那几个调用因为参数丢失而静默失效

### v0.2.2

- 开始转发后，镜像窗口一出现就把主界面收进托盘，屏幕留给投屏窗口（纯音频模式不会隐藏）

### v0.2.1

- 后台提示改为自绘窗口：原先的托盘气泡由宿主进程发出，通知栏里显示的是「Windows PowerShell」和 PowerShell 的图标
- 窗口标题与托盘提示不再带版本号，版本号只出现在启动日志里

### v0.2.0

- 新增「手机熄屏」按钮：转发过程中一键关闭手机面板，镜像不断流
- 新增托盘后台运行：关窗口 / 最小化收进通知区域，转发不中断；托盘菜单可直接启停、熄屏、退出
- 移除「投屏时手机熄屏」勾选框，改由运行中的按钮控制
- 修复：点关闭会连进程一起退出，托盘图标随之消失（`ShowDialog` 的模态循环在被 `Hide` 时直接结束）
- 修复：熄屏按钮状态判断改读 `SurfaceFlinger` 的 `powerMode`，不再被 `dumpsys display` 的假状态误导

### v0.1.0

- 首次发布：音频 / 音视频双通道转发，Wi-Fi 与 USB 两种连接，图形界面

## 致谢

- [scrcpy](https://github.com/Genymobile/scrcpy) — 音频转发与屏幕镜像的核心能力，作者 rom1v，Apache-2.0
- [Android platform-tools](https://developer.android.com/studio/releases/platform-tools) — adb

本项目只包含图形界面和流程编排，真正干活的是 scrcpy。

## 许可证

[MIT](LICENSE)
