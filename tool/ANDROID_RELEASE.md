# Android 发布

使用 `.github/workflows/build.yml` 的 Android 构建任务。现有 `--split-per-abi` 流程
分别生成 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` APK；仅启用 Android 输入即可独立
构建。`tag` 留空时只上传 Actions 构建产物，填写标签时同时上传到对应 Release。

正式构建必须配置 GitHub Actions Secrets：`SIGN_KEYSTORE_BASE64`、
`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`。PKCS12 密钥另设
`KEYSTORE_TYPE=PKCS12`，未指定时使用 JKS。私钥及密码不进入源码或发布包。

后续版本必须使用同一签名，以便覆盖升级。不同分支或其他作者签名的 APK 无法直接
覆盖安装。首次发布的签名备份应单独保存。
