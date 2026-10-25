# Android 发布

使用 `.github/workflows/build.yml` 的 Android 构建任务。正式版通过
`--target-platform android-arm64 --split-per-abi` 生成 `arm64-v8a` APK；仅启用 Android 输入即可独立
构建。`tag` 留空时只上传 Actions 构建产物，填写标签时同时上传到对应 Release。

打包前执行静态分析与 Flutter 回归测试。Linux 构建机需要 GTK 3、X11 与 Xi
开发库供上游新增的原生窗口管理依赖运行主机测试；工作流自动安装这些依赖。

正式构建必须配置 GitHub Actions Secrets：`SIGN_KEYSTORE_BASE64`、
`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`。PKCS12 密钥另设
`KEYSTORE_TYPE=PKCS12`，未指定时使用 JKS。私钥及密码不进入源码或发布包。

后续版本必须使用同一签名，以便覆盖升级。不同分支或其他作者签名的 APK 无法直接
覆盖安装。首次发布的签名备份应单独保存。
