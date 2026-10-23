# Tide English

[English](README.md) | **简体中文**

原生语言学习应用，通过自然对话练习表达、理解和词汇。包含 SwiftUI iOS 客户端、Jetpack Compose 安卓客户端，以及独立邮箱账户服务。

Tide English 默认使用你自己的模型 API Key。学习记录保存在设备上，注册登录为可选功能；托管语音、试用和购买默认关闭。仓库包含完整源码和锁定依赖，不包含用户密钥、个人签名或历史构建产物。

## 应用截图

<p align="center">
  <a href="docs/assets/screenshots/ios/zh-CN/talk.png"><img src="docs/assets/screenshots/ios/zh-CN/talk.png" width="24%" alt="带双语字幕的对话界面" /></a>
  <a href="docs/assets/screenshots/ios/zh-CN/themes.png"><img src="docs/assets/screenshots/ios/zh-CN/themes.png" width="24%" alt="对话主题选择" /></a>
  <a href="docs/assets/screenshots/ios/zh-CN/vocabulary.png"><img src="docs/assets/screenshots/ios/zh-CN/vocabulary.png" width="24%" alt="含中文释义的英语词汇" /></a>
  <a href="docs/assets/screenshots/ios/zh-CN/settings.png"><img src="docs/assets/screenshots/ios/zh-CN/settings.png" width="24%" alt="模型、界面语言与主题设置" /></a>
</p>
<p align="center">对话 · 主题 · 双语词汇 · 设置</p>

使用当前 iOS 应用在 iPhone 17 模拟器中实拍，展示中文界面与 Midnight 深色主题。内容来自离线示例，不含真实对话、API Key 或个人学习记录。[英文界面](README.md#screenshots) · [截图说明](docs/assets/screenshots/README.md)。

## 功能

| 功能 | 说明 |
| --- | --- |
| 多模型 | OpenAI、DeepSeek、GLM、Gemini 和自定义兼容接口；统一设置入口管理模型、地址与密钥 |
| 语音 | 支持原生实时语音；其他模型降级为设备识别、所选模型生成和系统朗读，设备不支持时保留打字 |
| 双语学习 | 独立学习语言和释义语言，双语字幕、词语查询、词汇释义和复习 |
| 个性化教学 | 对话纠错、主题、学习目标与能力证据，各语言独立记录 |
| 外观 | Paper、Midnight、Grove 主题；中文或英文界面，独立于学习语言 |
| 本地数据 | 对话、词汇、学习进度，支持手动备份与导入 |
| 可选账户 | 邮箱验证码登录、退出和删除；不启用学习云同步 |

实时音频模型受服务商能力限制，可能与设置中的文本模型不同。Android 设备语音需要 Android 12+ 可用本地识别与离线朗读语音；否则使用文字。Gemini 实时连接到期后需重连。模拟器测试不能证明真机麦克风、蓝牙或某个账户的模型访问权限。

## 目录结构

```text
tide-english/
├── mobile/
│   ├── ios/                 # SwiftUI、Swift 核心包、Xcode 工程与测试
│   │   ├── Application/
│   │   ├── Domain/
│   │   ├── Configuration/
│   │   └── TideEnglish.xcodeproj/
│   └── android/             # Compose、Kotlin 核心与 Gradle 工程
├── server/
│   ├── accounts/            # 邮箱验证码与账户服务
│   └── gateway/             # 默认不启用的可选托管网关
├── packages/
│   ├── contracts/           # 跨端协议
│   └── fixtures/            # 共享回归样例
├── tools/                   # 工程生成、内容导出与一致性检查
├── distribution/            # 发行模板和示例目录数据
└── docs/                    # 使用、开发、架构和运维指南
```

## 让 AI Agent 帮你安装到手机

把下面整段提示词发给能够访问本机文件、终端和手机的 Agent。它可以克隆仓库或使用已打开的工程，完成 iPhone 或安卓安装。两份 README 共用同一份英文提示词；账户登录、手机信任和权限由你在系统界面确认，密钥在 App 内填写。

```text
Help me build, install and launch Tide English on my iPhone or Android phone
from https://github.com/gd0306/tide-english.

Clone the repository into a new local folder, or use this checkout if already
open. Read AGENTS.md, README.md, docs/development/build-and-test.md and the
matching guide: docs/guides/iphone.md or docs/guides/android.md.

For iPhone, check Xcode and iOS tools, resolve pinned dependencies, run offline
Swift core tests and build the Simulator target. Guide me through Apple Account
and signing-team setup when needed. For Android, check JDK/SDK/adb and run the
Gradle unit tests, lint and debug build described in the guide.

For a first installation, help choose a unique application identifier if needed.
For updates, preserve the existing identifier, signing identity and Apple team.
Do not uninstall the app, clear learning data or bypass signing conflicts.

Detect my connected phone, build for that device, install and launch the app.
Tell me when to unlock it, trust the computer or developer profile, enable
Developer Mode or USB debugging, or approve a system prompt. Ask which device
only if the target is ambiguous.

I will select my languages and provider, then enter my key in Settings > Model
& API key. Never ask for the key in chat, read it from device secure storage,
or put it in source files or logs. Keep managed services, hosted trials and
purchases disabled. Do not deploy servers or start a live conversation.

Report which tests, build, signing, installation and launch checks passed,
iOS signing expiry if available, and anything I still need to do on the phone.
I will start the first live conversation.
```

## 本地运行

### iOS

准备支持 iOS 26.1 SDK 的 Xcode。纯 Swift 核心测试需要 Swift 6 工具链。在根目录执行：

```sh
python3 tools/generate_project.py
open mobile/ios/TideEnglish.xcodeproj
```

在 Xcode 添加 Apple Account，选择自己的签名 Team。默认 bundle identifier 为 `cn.gd306.tideenglish.ios`；如被占用，使用本机签名配置覆盖为自己的唯一标识。详见 [iPhone 指南](docs/guides/iphone.md)。

### Android

准备 JDK 17、Android SDK Platform 36 和 Build Tools 35.0.0，设置 `JAVA_HOME` 和 `ANDROID_HOME`：

```sh
cd mobile/android
./gradlew :app:assembleDebug
```

APK 输出到 `mobile/android/app/build/outputs/apk/debug/app-debug.apk`，应用标识为 `cn.gd306.tideenglish.android`。详见 [安卓指南](docs/guides/android.md)。

### 模型与账户

进入应用选择学习和释义语言，在 **设置 → 模型与 API 密钥** 填入自己的密钥。不要把密钥写进源码、日志或聊天。不同服务商与自定义地址分别保存凭据；改变发送对象后需要重新确认权限。详见 [模型与语音](docs/guides/models-and-voice.md)。

邮箱为可选组件。客户端沿用 `https://api.gd306.cn` 的邮箱账户合同，本次重建没有部署或修改该线上服务。自建实例见 [账户服务指南](docs/operations/accounts.md)。邮箱账户与托管网关是独立组件。

## 验证与开发

```sh
python3 -m unittest discover -s tools/tests -t .
python3 tools/export_android_content.py --check
python3 tools/check_cross_platform.py
swift test --package-path mobile/ios
```

完整命令见 [构建与测试](docs/development/build-and-test.md)，实际结果和限制见 [验证记录](docs/development/verification.md)。共享教学逻辑需要同步 Swift、Kotlin 与契约检查。

## 独立身份与学习数据

新工程使用独立应用标识，不会自动读取已有安装的沙箱或密钥。本次重建没有卸载应用、清理旧数据或修改线上数据库。需要迁移时，在原应用导出学习备份，再在新应用手动导入；模型密钥重新填写。不要为处理签名不匹配而卸载原应用。

发行模板、示例商品和价格不代表新应用已经上架或可支付。发布前需要自己的签名、商店应用和服务端配置，商业开关维持关闭直至单独验证完成。

官网、支持、隐私及条款链接使用保留的 `.example` 域名作为发行配置示例，尚未部署。对外发布前必须替换为自己实际提供的页面；这些示例地址不会用于模型请求或当前邮箱登录。

## 许可

[MIT License](LICENSE)，保留原始版权及第三方归属。来源见 [NOTICE](NOTICE)，贡献约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全处理见 [SECURITY.md](SECURITY.md)。
