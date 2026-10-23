# Tide English 独立工程设计

日期：2026-10-23。输入为本机已完成安卓功能的定制源码快照 `2fa9a7c`，并保留原仓库及其本地修改。

## 目标与边界

建立新的本地 Git 仓库，独立维护 Tide English 品牌、工程标识和文档。迁移 iOS、Android、邮箱账户及可选网关完整源码、测试、锁定依赖、契约与工具。排除旧构建产物、验证截图、历史执行记录、Git 历史、账户密钥和个人签名配置。保留 MIT 许可证及第三方归属。

显示名称使用 `Tide English`，类型、目标和模块使用 `TideEnglish`，配置前缀使用 `TIDE_ENGLISH`。iOS 标识为 `cn.gd306.tideenglish.ios`，Android 命名空间为 `cn.gd306.tideenglish`，应用标识为 `cn.gd306.tideenglish.android`。这是独立应用，不覆盖旧应用，不进行设备安装或生产部署。原有学习数据不作修改；用户可通过学习备份在新应用自行导入。密钥与账户凭据不包含在备份或源码迁移中。

## 目录与依赖

- `mobile/ios/`：`Application/`、`Domain/`、`Configuration/`、测试和 Xcode 工程。
- `mobile/android/`：Gradle 工程，Kotlin 包目录与新命名空间一致。
- `server/gateway/`：可选托管网关及其 PostgreSQL 迁移、协议测试。
- `server/accounts/`：现有邮箱验证码账户服务源码与部署模板。
- `packages/contracts/`、`packages/fixtures/`：跨端契约与回归样例。
- `tools/`：工程生成、内容导出、兼容性和发行检查。
- `distribution/`：发行模板和目录数据。历史发布截图和执行证据不作为新项目的发布证明。
- `docs/`：新项目指南、架构与操作说明。

同步更新源码符号、文件名、项目引用、构建变量、资源键、包路径、客户端与服务端内部协议和 CI 路径。默认保留自有 API Key 模式，托管、购买及试用关闭；邮箱客户端继续使用既有 `https://api.gd306.cn` 合同。商业功能的旧账户、商店商品和历史配置不得作为新应用的生产配置复用。

## 验收

源码与路径扫描不含旧项目品牌；新 README 包含功能、真实限制、目录、依赖、构建及数据迁移说明；跨平台契约检查、工具测试、Swift 核心测试与 iOS Simulator 构建、Android JVM 测试/Lint/APK 构建、账户和网关离线测试通过。保留原项目不变，不使用真实模型密钥，不发送邮件，不部署服务。
