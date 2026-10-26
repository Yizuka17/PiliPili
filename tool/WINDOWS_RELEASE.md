# Pilipili Windows 发布

2.1.6：其它设置新增“悬停高亮”，音视频设置新增“应用内音量”。两项默认保持原有
行为，修改即时生效，并使用原有设置表参与 WebDAV 备份。PC 亮度按当前显示器检测，
Windows 内置面板使用 WMI，外接显示器使用 DDC/CI；不可用时左侧回退到音量。
更新检查按版本号与构建号排序，正式版跳过预发布版本。

采用仓库指定 Flutter 版本（`.fvmrc`/`pubspec.yaml`），执行 `lib/scripts/build.ps1` 生成版本、提交和时间信息，再应用 `lib/scripts/patch.ps1 windows` 中的框架及 UI 补丁。Windows 安装包使用仓库原有 Inno Setup 模板及 AppId，与旧版安装兼容。

安装器从 HKLM/HKCU 的 32/64 位卸载记录读取旧安装目录，兼容 AppId 的普通及花括号形式，
并确认目录内存在 `pilipili.exe` 或旧名 `piliplus.exe`。检测到已有安装时直接沿用目录并跳过路径选择页；
无有效旧安装时保留首次安装的目录选择。CI 使用实际编译的安装器验证各类注册表记录、自定义路径、
旧可执行文件替换和失效记录。回归脚本只允许在可丢弃的 GitHub Actions runner 上运行。

```powershell
./tool/build_windows_touch_debug.ps1 -PortableCMake -Mode release -Production
./tool/package_windows_release.ps1 -InnoCompiler 'C:/path/to/Inno Setup 6/ISCC.exe'
```

不需要便携 CMake 时可省略 `-PortableCMake`。第一条命令运行 Dart 分析、Flutter 测试和原生触摸测试，构建 Release 并附带可分发的 MSVC Release 运行库；`-Production` 关闭详细触摸记录。普通错误日志由应用设置控制。

第二条命令直接渲染与 Fastforge 相同的 `windows/packaging/exe/inno_setup.iss` 和 `make_config.yaml`，生成安装程序。产物在 `dist/`，附有 SHA-256 校验文件。`.exe` 安装包无需证书，也不要求导入根证书。

关于 → 错误日志存储位置：可选择目录或恢复默认文档目录，重启生效。原目录中的 `.pili_logs.json` 保留；自定义目录不可用时回退到文档目录。详细触摸 JSONL 日志是独立的诊断功能，正式版默认不写入。

品牌名称为 Pilipili。Windows 数据目录仍使用原有 `com.example/piliplus`；移动端包标识、平台通道、WebDAV 设置备份标识及安装 AppId 保持兼容，以保留登录、设置和下载。历史问题引用和原作者版权声明保留。
