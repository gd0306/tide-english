# 独立工程验收记录

日期：2026-10-23。本记录描述本机源码、测试和构建验证，不代表生产部署或商店发布。

2026-11-02 更新：App 内账户登录现已默认关闭，账户服务地址默认留空；需要时按安装指南显式配置和启用。下文保留 10 月 23 日的验收结果。

## 2026-11-04 词汇与主题页布局

保留 Paper/Midnight/Grove 主题，将词汇页顶部翻译改为紧凑输入、编辑时展开，收起保留草稿；空译文不占位。词汇页缩小标题并将释义语言放到词条前；辅助功能字号下释义语言纵排，输入区随字号缩放。主题页去除展示型引导区，保留场景图标与纸面卡片，缩小卡片留白。

| 验证 | 本轮结果与证据 |
| --- | --- |
| 离线核心与工具 | Swift 389 项、Android JVM 460 项、根工具 92 项通过；语言导出、跨端契约检查通过。日志：`.build/layout-swift.log`、`.build/layout-android-final.log`、`.build/layout-tools.log` |
| 构建 | iOS arm64 模拟器应用与 UI 测试构建通过；Android Debug、隔离 UI 测试 APK 和 Lint 通过（零错误，100 个警告、6 个提示）。未进行本轮发行签名构建 |
| iOS UI | 专用 iPhone 17 / iOS 27 模拟器；翻译、换向、清空、中文选择器、首屏词条与草稿保留、四个首屏话题及选择、三主题跨页切换，共 5 项针对性用例通过。证据：`.build/layout-green.xcresult`、`.build/layout-themes.xcresult`；字号调整后的翻译复验见 `.build/layout-final.xcresult` |
| Android UI | 专用 API 35 arm64 模拟器，仅安装 `.uitest` 与测试包；紧凑翻译草稿及核心页面验证共 2 项通过。证据：`.build/layout-android-ui.log`；原始截图：`.build/layout-android-screens/` |
| 文档截图 | README 中英文主题页与词汇页使用离线 fixture 重新拍摄；保留原始原生分辨率，日期、文件大小和 SHA-256 同步到截图清单 |

以上为离线与模拟器检查，未覆盖真机、在线模型、VoiceOver/TalkBack 或启动时间/帧率。未更改账户默认值、学习档案、模型协议或服务器配置，不需要服务端部署。此前审查中全局导航字号限制、跨端品牌统一及完整语言名称本地化仍属于后续范围。

### 随后完成的真机与在线验证

2026-11-04 在已配对的 iPhone 17 / iOS 27.2 上覆盖安装 Release `1.0 (10)`。沿用手机既有安装标识和签名团队，仅通过本机构建参数覆盖配置，未写入仓库；未卸载应用。旧构建签名已过期，已刷新至北京时间 2026-11-11 15:34。

- 真机端到端用例复测通过：顶部翻译默认紧凑、已有词条首屏可操作、展开/收起保留草稿、清空隐藏空译文、至少四个话题首屏可选、选择后进入对话页。证据：`.build/device-verification/layout-phone-ui-final.xcresult`，1 项通过、零失败/跳过。
- 使用手机现有 DeepSeek 配置实际将 `Hello!` 翻译为 `你好！`，未使用预览 fixture 或替换模型密钥。未启动真实语音会话或测量语音性能。
- 真机截图发现翻译按钮继承了正文深色文字，已改用主题的 `onAccent` 文字色并重装确认。Paper/Midnight/Grove 令牌对比分别为 7.96:1、8.33:1、5.47:1；修复后真机截图显示白字可读。
- 覆盖前后本地备份核对：49 条学习记录的完整内容及偏好设置均一致。个人签名配置未写入源码，备份、真机截图与测试产物仅保留在被忽略的 `.build/`，未用于公开 README 截图。

## 工程身份

- 独立本地 Git 仓库，未配置远程或推送。
- 显示名 Tide English；Xcode 工程、scheme 与应用目标 TideEnglish；Swift 核心模块 TideEnglishCore。
- iOS：`cn.gd306.tideenglish.ios`，版本 `1.0 (1)`，未带入个人 Team。
- Android：命名空间 `cn.gd306.tideenglish`，应用标识 `cn.gd306.tideenglish.android`，版本 `1.0 (1)`。
- 模型自有密钥模式；托管、Google/Apple 托管登录和购买默认关闭。可选邮箱继续使用 `https://api.gd306.cn` 合同。
- 两端学习备份使用既有 schemaVersion 1/2，没有品牌 magic 字段；原备份可手动导入，模型密钥不随备份迁移。

## 实际结果

| 检查 | 结果 | 本机证据 |
| --- | --- | --- |
| Swift 核心 | 381/381，零失败 | `.swift-test.log` |
| iOS Simulator 应用 | 双架构构建成功；最终 Info.plist 身份、版本和关闭开关正确 | `.build/ios-final-build.log` |
| Android JVM | 452/452，零失败、错误或跳过 | `mobile/android/app/build/test-results/testDebugUnitTest/` |
| Android Lint | 零错误，94 个警告、6 个提示 | `mobile/android/app/build/reports/lint-results-debug.xml` |
| Android 构建 | Debug、UI 测试 APK 与显式 opt-in voice 验证 APK 编译成功 | `.build/android-validation/` |
| Android UI | Caption 16 项、其他界面及生命周期 41 项，共 57 项全部通过 | `.build/android-validation/ui-results.json` |
| Gateway | TypeScript check/build 成功；独立 PostgreSQL 下 533/533，零跳过 | `.build/gateway-tests.log` |
| Accounts | 独立 PostgreSQL 下 25/25，零跳过 | `.build/accounts-tests.log` |
| 部署边界 | 本地新构建镜像及隔离容器下 5/5 | `.build/accounts-boundaries.log` |
| 工程工具 | 92/92；语言导出和跨端契约检查通过 | `.build/tools-tests-final.log` |
| 秘密扫描 | 固定版本 Gitleaks 8.30.1，源码扫描未发现凭据 | `.build/security/scan-final.log` |
| 发行模板 | 品牌与文案检查通过；缺少新商店素材时仍阻止正式发行验收 | `.build/distribution-check.json` |

扫描中的单一过期 JWT 是已有的合成 HMAC 回归样例，使用公开 fixture 字符串签名。扫描配置仅对该文件的完整固定测试值作精确例外，不排除其他令牌。

Android UI 使用新建的 API35 AOSP arm64 模拟器 `emulator-5558`，仅安装 `.uitest` 与其测试包。两个分组分别运行，全部使用合成数据；测试后已关闭该模拟器。服务测试使用随机临时容器、独立测试库与模拟 SMTP；临时数据库容器已清理，没有操作已有生产容器或数据卷。

独立复审未发现剩余 Important/Critical 问题。复审指出的动态诊断地址和支持邮箱遗漏已修复，并重新编译相关目标。原功能测试断言保留；仅将旧发行历史断言改为新工程独立身份、关闭购买和非生产预览约束。

## 构建产物

- Android APK：`.build/artifacts/TideEnglish-Android-1.0.apk`，65,140,014 字节。
- SHA-256：`6668acc0c649874d078979f19881bbad423a7a58dbe0ca28e9dceaa6e467739d`。
- APK Signature Scheme v2 校验通过，使用标准本地调试签名，不是商店发行签名。
- iOS 模拟器应用：`.build/ios/Build/Products/Debug-iphonesimulator/TideEnglish.app`。

所有产物、下载工具、依赖缓存与运行日志都在 Git 忽略范围；新源码不依赖本机缓存的绝对路径。

## 验证边界

未运行 iOS UI 自动化，未安装或卸载真机应用，未读取用户 API Key、SMTP 授权码或设备 Keychain，未发送真实邮件、发起真实模型调用或支付。手机录音、蓝牙、服务商权限、个人签名与商店发布仍需各自验证。

GitHub Actions 路径、依赖检查、服务测试和安卓 UI 分组已更新；本地新仓库尚未运行远程 Actions。官网、隐私、支持及条款页面仍使用明确的 `.example` 发行示例地址，发布前必须配置真实页面。发行截图、feature graphic 和商店图标未生成，带 `--require-assets` 的发行检查会拒绝缺失素材。

本次没有部署新服务，也没有改变现有线上邮箱 API。MIT 版权及第三方声明保留，原项目及其本地修改保留。
