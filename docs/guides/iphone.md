# 在 iPhone 上运行

准备支持 iOS 26.1 的 Xcode。根目录执行 `python3 tools/generate_project.py`，打开 `mobile/ios/TideEnglish.xcodeproj`，选择 TideEnglish scheme。

在 Xcode → Settings → Accounts 添加自己的 Apple Account。在 Signing & Capabilities 选择 Team 并启用自动签名。本机覆盖放在 `mobile/ios/Configuration/Local.xcconfig`，可由同目录 Local.example.xcconfig 复制；该文件已忽略。

默认标识 cn.gd306.tideenglish.ios。如被占用，使用自己的唯一标识，在本机配置覆盖 PRODUCT_BUNDLE_IDENTIFIER。连接手机、解锁并信任电脑，按需启用 Developer Mode，再选择设备运行。免费签名需定期重新签名，以实际 provisioning profile 的到期日为准。

启动后选择语言、在统一模型设置填写密钥，并在手机上批准需要的权限。构建不会自动发起真实对话。

这是新的独立应用。更新时保留相同 Team、标识与签名，不卸载来修复签名问题。学习迁移用手动备份导入；密钥重新填写。
