# Windows 触摸诊断版

引擎：Flutter **3.49.0-0.2.pre**（beta），引擎 revision
`774a76734848e38c908681d752e465b2a1595adb`，包含 Flutter #190029。
项目的 `pubspec.yaml` 和 `.fvmrc` 都锁定该 SDK，CI 的 SDK 下载渠道同步为 beta。

v2 在主窗口和实际接收输入的 Flutter 子窗口关闭 Windows 的长按转右键，
保留 Flutter 自己的长按、拖动和缩放识别。播放器的鼠标全屏快捷键还会
校验输入类型和指针配对，避免触摸/笔或其他指针的松手触发它。
首版实测日志显示：触摸长按松手后 1–2 ms 出现 `mouse / buttons=2`，
随后触发应用内全屏。Windows 行为见
[微软说明](https://devblogs.microsoft.com/oldnewthing/20170227-00/?p=95585/)。

v3 试验修复触摸后的鼠标悬停残留：触摸开始时向 Flutter 发送鼠标离开，
仅在触摸模式下拦截 `sourceDevice=0 / sourceOrigin=4` 且无鼠标按键的
系统生成 `WM_MOUSEMOVE`。真实鼠标、触控板及应用注入的鼠标输入恢复鼠标模式；
笔悬停、触摸原始事件和鼠标按键继续转发。鼠标拖动期间触摸不会清除该鼠标指针。
修复仍需实际触摸设备复测，日志会标记 `suppressed=true` 和 `clearTouchHover`。

v4 补充窗口切换处理：其他窗口里使用鼠标，再通过三指手势或触摸任务栏返回时，
系统手势的触摸按下不会送到 Pilipili。主窗口收到 `WM_ACTIVATE` 后清除旧鼠标
悬停，以当前屏幕光标位置为基准等待新的鼠标动作。系统位置刷新及位置未变化的
鼠标移动不恢复悬停；真正移动鼠标、点击或滚轮立即恢复。鼠标按住拖动时保留指针，
笔悬停和键盘焦点继续正常工作。启动时也建立同样的基准，避免触摸启动后出现旧悬停。

## 使用

v5 将窗口切回时的静止光标过滤也应用于应用内触摸开始：记录当前屏幕光标位置，
不将同位置的鼠标/未知来源刷新当作新的鼠标动作。实际移动、点击、滚轮及按住鼠标
拖动继续工作。“其它设置 → 悬停高亮”可独立关闭高亮显示。

提供两种包：`touch-debug` 是真正的 Flutter Debug 构建，目标电脑需安装
Visual Studio/Build Tools 的 C++ Debug 运行库。`touch-release` 是适合普通测试机的
诊断构建，保留相同触摸日志并附带可分发的 MSVC Release 运行库。
两者使用相同的新引擎和输入处理代码；普通触摸设备优先使用 `touch-release`。

解压完整压缩包，运行 `pilipili.exe`；exe、DLL 和 `data` 必须放在一起。
在播放设置开启上下滑动进入/退出全屏，再用触摸屏测试：

1. 中间区域单指上下滑动切换全屏。
2. 随后单指左右滑动调整进度、单击显示控制栏、双击播放/暂停。
3. 长按倍速，手指保持在视频区域松开，观察是否误进全屏。
4. 双指缩放，再切回单指；最后测试鼠标点击、双击和中键/右键全屏。
5. 长按评论打开选项，松手后菜单应保持；关闭后检查该评论是否仍有悬停高亮。
6. 普通点击评论和视频列表，松手后观察高亮；随后移动真实鼠标，确认悬停立即恢复。
7. 在其他窗口使用鼠标，再通过触摸任务栏或三指手势切回；检查是否出现旧位置的高亮。
   不动鼠标时悬停应保持清除，随后实际移动或点击鼠标应恢复鼠标操作。

每次启动生成一个 JSONL 日志：`%TEMP%\Pilipili-touch-logs\touch-*.jsonl`。
不依赖设置里的错误日志开关。输入日志每秒落盘，关闭软件后可运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\collect_touch_logs.ps1
```

日志压缩包保存到脚本所在目录。也可直接把日志目录中的对应文件发回。
记录时间、鼠标/触摸/笔类型、pointer ID、按键、坐标、移动量、活动指针、
鼠标与触摸同时按下标记、播放器缩放指针数、长按、双击和全屏状态。
v2 还记录原生 Windows 消息、消息来源、额外标记、捕获状态、窗口配置是否成功，
以及评论菜单打开/关闭。鼠标 hover 每 100 ms 最多一条，原生移动每 16 ms 最多一条。
v3 的 `nativeCursor` 记录屏幕/Flutter 窗口内光标坐标、显示状态、因触摸/笔被系统
隐藏的 `suppressed` 标记、光标句柄及窗口 DPI；原生输入事件同时附带光标快照。
光标采样仅在应用位于前台时进行，每 100 ms 检查一次，状态变化即记录，静止时每 2 秒一条。
`widgetState` 记录主评论、子评论、横向/纵向视频卡片的 `hovered / pressed / focused`、
组件匿名编号、逻辑坐标范围和最近的 Flutter 输入，可区分悬停、按下和焦点高亮。
组件日志不含评论内容或视频标题。`nativeCursor` 使用物理像素，`widgetState` 与
Flutter 指针使用经过应用缩放的逻辑像素，比较时需留意 DPI 与应用缩放。
v4 还记录 `WM_ACTIVATE / WM_ACTIVATEAPP / WM_MOUSEACTIVATE / WM_SETFOCUS / WM_KILLFOCUS`、
`awaitingMouseActivity` 和 `clearReentryHover / resetReentryHover`，帮助核对窗口切换前后的状态。
窗口坐标变化不会算作鼠标移动；比较使用真实屏幕光标位置，不设恢复等待时间。
日志不记录账号、输入文本、网络请求或视频内容。
单次启动最多记录 64 MiB，达到上限后停止；重启软件开始新日志。
时间使用 UTC，`elapsedUs` 是启动后的单调时钟；日志首行包含 SDK/引擎版本。

## 重新构建

```powershell
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1
# 若只有 MSVC/Windows SDK、缺少 Visual Studio 的 CMake 组件：
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1 -PortableCMake
# 普通测试机可用的诊断构建，触摸日志同样启用：
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1 -PortableCMake -Mode release
# v2 使用独立文件名，保留上一版包供对比：
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1 -PortableCMake -Mode release -ArtifactSuffix v2
# v3 增加光标与组件状态记录，试验清理触摸后的悬停：
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1 -PortableCMake -Mode release -ArtifactSuffix v3
# v4 补充通过任务栏/系统手势返回窗口时的悬停清理：
pwsh -NoProfile -File tool/build_windows_touch_debug.ps1 -PortableCMake -Mode release -ArtifactSuffix v4
```

流程参照 `.github/workflows/win_x64.yml`：`lib/scripts/build.ps1` 生成构建信息，
`lib/scripts/patch.ps1 windows` 应用项目要求的 Flutter/Material UI 补丁，
运行 Dart 分析和测试，然后构建所选模式；默认 Debug 使用 `flutter build windows --debug --no-pub`。
随后运行原生窗口测试，验证主/子窗口关闭系统长按手势、原始触摸与真实右键消息
仍能转发、原生日志通道有效以及窗口清理正确。测试窗口不会显示。
两种诊断版都使用便携 zip，无需安装器依赖 fastforge/Inno Setup。
Release 诊断版从本机 Visual Studio 的 `VC/Redist/MSVC` 目录附带 x64 CRT DLL，
不会分发不可再分发的 Debug CRT。该目录必须存在。
Release 诊断包会检查并排除 ANGLE 附带、未被任何随包程序或 DLL 引用的
Debug `zlib.dll`；若发现引用则构建报错，避免遗漏实际依赖。
脚本会在缺少 NuGet 时下载带有效签名的 NuGet 6.14.0，供 WebView 插件恢复原生依赖。
脚本使用 `.fvm/flutter_sdk` 和独立 `.fvm/pub-cache`，恢复构建前的 pubspec 版本字段。
`-PortableCMake` 仅对独立 SDK 的工具检测增加便携 CMake 路径和 VS 2022 选择，
不改引擎输入处理；本机仍需具备 MSVC x64 编译器、MSBuild 和 Windows SDK。
源代码补丁以 `.fvm` 内 SDK 的实际版本为准，不允许跳过失败的项目补丁。

产物：`dist/Pilipili-Windows-touch-debug-flutter-3.49.0-0.2.pre.zip`。
普通测试机诊断版：`dist/Pilipili-Windows-touch-release-flutter-3.49.0-0.2.pre.zip`。
构建信息见随包 `touch-debug-build.json`。
