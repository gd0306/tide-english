# 独立工程验收记录

日期：2026-10-23。本记录描述本机源码、测试和构建验证，不代表生产部署或商店发布。

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
