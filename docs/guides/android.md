# 在 Android 上运行

准备 JDK 17、Android SDK Platform 36、Build Tools 35.0.0，设置 JAVA_HOME 和 ANDROID_HOME。在 mobile/android 运行 `./gradlew :app:assembleDebug`。

APK 位于 app/build/outputs/apk/debug/app-debug.apk，应用标识 cn.gd306.tideenglish.android，最低 Android 8.0/API26。可以文件管理器打开 APK，按系统提示允许安装来源；或明确指定设备序列号执行 `adb -s DEVICE_SERIAL install -r app/build/outputs/apk/debug/app-debug.apk`。

不要在多设备环境省略序列号，也不要卸载来绕过签名冲突。调试签名用于开发，发布需要自己的签名配置与安全备份。独立标识不会读取其他应用的档案。

应用内选语言、配置模型。Android12+ 且有本地识别与离线朗读语音时可使用设备语音降级，否则文字输入。麦克风、蓝牙、前后台行为和模型权限需要真机验证。

默认不显示账户登录入口，也不会恢复账户会话或连接账户服务。使用自己的模型密钥即可学习和翻译，无需 SMTP、OAuth 或账户服务器。

仅在明确需要邮箱账户并准备好自己的兼容账户服务时，在被忽略的 `local.properties` 中设置 `TIDE_ENGLISH_EMAIL_ACCOUNTS_ENABLED=true` 和 `TIDE_ENGLISH_EMAIL_ACCOUNT_API_URL=https://accounts.example.test`，将示例地址替换为自己的服务后重新构建。账户功能不启用学习云同步，Google/Apple 登录、托管和购买仍需单独配置。
