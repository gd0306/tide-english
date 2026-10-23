# 构建与测试

准备 Xcode、Python3、Node22.19+、JDK17、SDK36和Build Tools35.0.0。沿用锁定依赖；首次构建可能需联网下载，缓存齐全后可离线。

## 公共工具

根目录运行：

```sh
python3 -m unittest discover -s tools/tests -t .
python3 tools/export_android_content.py --check
python3 tools/check_cross_platform.py
```

语言源在 mobile/ios/Domain/Languages，修改后运行 `python3 tools/export_android_content.py` 更新Kotlin，并检查共享策略和档案字段。

## iOS

```sh
python3 tools/generate_project.py
swift test --package-path mobile/ios
xcodebuild -project mobile/ios/TideEnglish.xcodeproj -scheme TideEnglish -configuration Debug -sdk iphonesimulator -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
```

纯核心使用Swift6，模拟器应用部署目标iOS26.1。签名覆盖写在被忽略的Configuration/Local.xcconfig，不写进生成器。

## Android

```sh
cd mobile/android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleUiTestAndroidTest
```

缓存齐全后可加 --offline --max-workers=2。界面测试使用.uitest独立包，明确指定模拟器；不得读取真实用户安装的档案和密钥。真实语音需单独验证。

## 邮箱账户

```sh
cd server/accounts
npm ci --ignore-scripts
npm test
```

根目录部署边界测试：`python3 server/accounts/deploy/test-boundaries.py`。完整集成测试需要独立测试数据库和ACCOUNTS_TEST_DATABASE_URL，不能使用生产库。使用合成验证码和SMTP fixture，不向真实邮箱发信。

## 可选网关

```sh
cd server/gateway
npm ci --ignore-scripts
npm run check
npm run build
npm test
```

数据库测试需独立PostgreSQL测试库，使用TEST_DATABASE_URL。区分通过、跳过与未运行。示例商业配置不用于生产，不为构建启用托管或购买。
