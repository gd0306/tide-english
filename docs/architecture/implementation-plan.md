# Tide English 工程重建执行计划

**目标**：交付独立、可构建的 Tide English 源码工程，而不是仅更换显示名。

**设计**：[project-renewal.md](project-renewal.md)。iOS 与 Android 保持原生实现；源码迁移按工程边界分工，最后统一验证。

## 全局约束

原项目只读。新目录 `/Users/gd/Git/excel_personal/tide-english`。不复制忽略的本地文件、密钥、构建结果、历史审计及个人签名设置。生产服务与手机数据不变。依赖不升级。保留许可证。默认托管和购买关闭。

- [x] 导出已跟踪的有效源码，建立新目录映射和统一品牌替换，初始化独立 Git 仓库。
- [x] iOS：修复 Xcode 生成器、Swift 包、资源及标识；执行 `swift test --package-path mobile/ios` 和 `xcodebuild -project mobile/ios/TideEnglish.xcodeproj -scheme TideEnglish -sdk iphonesimulator -configuration Debug -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build`。
- [x] Android：修复包目录、Gradle 属性、测试路径和资源；执行 `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleUiTestAndroidTest`，个人功能标志保持关闭。
- [x] 服务与契约：修复移动后的样例路径、服务名称、协议、环境模板及部署模板；在两个服务目录执行离线测试与网关 TypeScript 检查，执行跨平台契约工具。
- [x] 文档与工具：重写 README、开发指南、贡献与安全说明，更新 CI；删除不适用于新项目的历史发布声明，保留功能依赖的发行数据。
- [x] 扫描旧名称、无效工程引用、私密文件和本机绝对路径；记录实际验证结果并完成独立仓库初始提交。

测试中的夹具、测试名称与产品行为断言随标识同步迁移，不能通过删掉功能断言来使重构通过。
