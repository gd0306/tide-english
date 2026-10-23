# Tide English

原生语言学习应用，通过自然对话练习表达、理解和词汇。包含 SwiftUI iOS 客户端、Jetpack Compose 安卓客户端，以及独立邮箱账户服务。

Tide English 默认使用你自己的模型 API Key。学习记录保存在设备上，注册登录为可选功能；托管语音、试用和购买默认关闭。仓库包含完整源码和锁定依赖，不包含用户密钥、个人签名或历史构建产物。

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

先用 Agent 打开或附加这个工程目录，再把下面整段提示词发给它。提示词同时适用于 iPhone 和安卓；Agent 需要具备本机文件、终端和设备访问能力。Apple Account 登录、系统密码、手机信任和权限确认仍由你在系统界面完成，无需把任何密钥或密码发到聊天中。

```text
请将当前 Tide English 工程构建、安装并启动在我连接的手机上，持续执行到完成，不能只给我安装教程或停在生成安装包。

工程位置是当前打开或附加的 tide-english 目录。先确认 README.md、mobile/ios、mobile/android 和 tools/generate_project.py 存在；若当前环境没有源码访问权限或找不到工程，只向我索取实际源码目录或仓库地址，不要猜测下载地址。本工程是否已有远程地址，以 git remote -v 的实际结果为准。

执行要求：
1. 先阅读 AGENTS.md、README.md、docs/development/build-and-test.md，以及目标平台的 docs/guides/iphone.md 或 docs/guides/android.md。检查现有改动并保留它们，沿用锁定依赖，不重置仓库、不升级依赖、不顺带重构功能。
2. 自动检测本机操作系统、开发工具和已连接的真实手机，区分真机与模拟器。只有一台真机时使用它；没有连接、尚未授权或有多台无法确定目标时，明确告诉我需要连接、解锁、授权或选择哪台。所有安装命令必须指定目标设备，不能安装到其他手机；不能把模拟器成功当成手机安装成功。
3. 我授权你完成本次安装所需的正常工具检查、依赖解析、测试、构建、签名、安装和启动，不必反复询问是否继续。遵守当前 Agent 的权限规则；系统授权、账户登录或缺少必要信息时，说明具体阻碍和我需要完成的动作，完成后接着执行。不要索取系统密码、Apple 验证码、模型 API Key 或邮箱授权码。

iPhone 路径：
4. 必须在具备 Xcode 的 macOS 上构建。检查 Xcode 版本、开发者目录、首次启动状态、iOS SDK 和设备支持。读取 tools/generate_project.py，使用 mobile/ios/TideEnglish.xcodeproj 和 TideEnglish scheme。已有工程优先直接构建；仅在工程缺失或确需同步引用时运行生成器，并先保留现有工程修改、将已有 Team 和标识覆盖保存到被忽略的 Configuration/Local.xcconfig，避免重新生成时丢失签名设置。解析固定版本的包依赖，运行 Swift 核心测试和 iOS Simulator 构建；缓存齐全时优先离线，不绕过正常代码签名。
5. 检查当前 Team、bundle identifier 和目标手机上的安装状态。首次安装默认使用 cn.gd306.tideenglish.ios，若标识不可用，配置自己的唯一标识；如需 Apple Account 或 Team，指导我在 Xcode 界面完成。更新同一应用时保留已有 Team、标识和签名。本机覆盖写入被忽略的 mobile/ios/Configuration/Local.xcconfig，不将个人签名配置或私钥提交到 Git。
6. 使用配置好的 Team 为目标真机构建，通过 Xcode 或本机 xcrun devicectl 安装并启动。命令参数先以本机 --help 为准。遇到锁屏、信任此电脑、Developer Mode、开发者描述文件信任或系统授权时，明确提示我在什么界面操作。读取构建产物的 provisioning profile 到期日期并报告；不要导出签名私钥或读取模型密钥。

Android 路径：
7. 检查 JDK 17、Android SDK Platform 36、Build Tools 35.0.0 和 adb；按需要配置本机 JAVA_HOME、ANDROID_HOME 或被忽略的 local.properties。用 adb devices -l 检测设备；unauthorized 时提示我解锁并确认 USB 调试，offline 时先恢复连接，不清除手机数据。
8. 在 mobile/android 使用仓库 Gradle Wrapper 解析锁定依赖，运行 :app:testDebugUnitTest、:app:lintDebug 和 :app:assembleDebug。默认应用标识为 cn.gd306.tideenglish.android；首次安装使用本机调试签名，更新时使用与已有安装相匹配的签名。核对最终 APK 的标识、签名和个人版开关，再用 adb -s 目标序列号 install -r 安装并启动主 Activity。不得为解决签名或版本冲突而卸载、清除数据、强行降级或擅自换标识；无法匹配时保留原安装并报告具体原因。

两个平台共同要求：
9. 保留现有应用、学习记录和密钥。发现不同应用标识的同名旧应用时，作为独立安装保留它，不擅自覆盖或自动迁移；学习记录可由我手动备份导入。不得读取、导出或记录设备中的模型密钥、账户令牌及个人学习内容。
10. 保持托管、试用、购买和学习云同步关闭，不部署服务端、不修改线上数据库、不发送验证码邮件、不发起真实模型请求或语音通话。可选邮箱登录不应成为本地学习的前置条件。安装后由我自己选择学习、释义和界面语言，并在“设置 → 模型与 API 密钥”填写密钥。
11. 用设备工具实际确认安装与启动结果。最后报告：目标手机、应用标识与版本、哪些测试/构建/签名/安装/启动检查通过、产物路径、iOS 签名到期时间（若可取得），以及还需要我在手机上完成什么。失败或受阻的步骤如实说明，不能将仅编译成功表述为已安装。第一次真实对话由我自己发起。
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
