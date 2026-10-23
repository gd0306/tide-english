# Tide English

**English** | [简体中文](README-CN.md)

A native language-learning app for practising expression, comprehension and vocabulary through natural conversation. The project includes a SwiftUI iOS client, a Jetpack Compose Android client and a separate email account service.

Tide English uses your own model API key by default. Learning records stay on your device, and signing in is optional. Hosted voice, trials and purchases are disabled by default. This repository contains the full source and pinned dependencies, without user credentials, personal signing settings or historical build artifacts.

## Screenshots

<p align="center">
  <a href="docs/assets/screenshots/ios/en/talk.png"><img src="docs/assets/screenshots/ios/en/talk.png" width="24%" alt="Conversation with bilingual captions" /></a>
  <a href="docs/assets/screenshots/ios/en/themes.png"><img src="docs/assets/screenshots/ios/en/themes.png" width="24%" alt="Conversation themes" /></a>
  <a href="docs/assets/screenshots/ios/en/vocabulary.png"><img src="docs/assets/screenshots/ios/en/vocabulary.png" width="24%" alt="English vocabulary with Chinese definitions" /></a>
  <a href="docs/assets/screenshots/ios/en/settings.png"><img src="docs/assets/screenshots/ios/en/settings.png" width="24%" alt="Model, interface language and theme settings" /></a>
</p>
<p align="center">Conversation · Themes · Bilingual vocabulary · Settings</p>

Captured from the current iOS app on an iPhone 17 simulator using offline sample data. English interface with the Paper theme; no real conversation, API key or personal learning record is shown. [Chinese interface](README-CN.md#应用截图) · [Capture details](docs/assets/screenshots/README.md).

## Features

| Feature | Description |
| --- | --- |
| Multiple providers | OpenAI, DeepSeek, GLM, Gemini and compatible custom endpoints; one settings screen for provider, model, endpoint and key |
| Voice conversations | Native realtime voice where supported; other models use device recognition, the selected model and system speech, with typing available when device voice is unsupported |
| Bilingual learning | Independent learning and explanation languages, bilingual captions, contextual word lookup, vocabulary definitions and review |
| Personalized teaching | Corrections, topics, learning goals and capability evidence, recorded separately for each language |
| Appearance | Paper, Midnight and Grove themes; Chinese or English interface, independent of the learning language |
| Local data | Conversations, vocabulary and learning progress, with manual backup and import |
| Optional accounts | Email-code sign-in, sign-out and account deletion; no learning-data cloud sync |

Realtime audio models depend on provider capabilities and may differ from the selected text model. Android device voice requires Android 12+ with available on-device recognition and an offline reading voice; otherwise, use typing. Gemini realtime connections require reconnection after expiry. Simulator tests do not establish physical microphone quality, Bluetooth behavior or model access for a particular account.

## Project structure

```text
tide-english/
├── mobile/
│   ├── ios/                 # SwiftUI, Swift core package, Xcode project and tests
│   │   ├── Application/
│   │   ├── Domain/
│   │   ├── Configuration/
│   │   └── TideEnglish.xcodeproj/
│   └── android/             # Compose, Kotlin core and Gradle project
├── server/
│   ├── accounts/            # Email-code authentication and account service
│   └── gateway/             # Optional hosted gateway, disabled by default
├── packages/
│   ├── contracts/           # Cross-platform contracts
│   └── fixtures/            # Shared regression fixtures
├── tools/                   # Project generation, content export and consistency checks
├── distribution/            # Release templates and example catalog data
└── docs/                    # User, development, architecture and operations guides
```

## Let an AI agent install the app on your phone

Paste the prompt below into a coding agent with access to your local files, terminal and phone. It can clone the repository or use an open checkout. Complete account sign-in, device trust and permissions yourself; enter passwords and API keys only in the system or app UI.

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

## Run locally

### iOS

Prepare Xcode with support for the iOS 26.1 SDK. Pure Swift core tests require a Swift 6 toolchain. From the repository root:

```sh
python3 tools/generate_project.py
open mobile/ios/TideEnglish.xcodeproj
```

Add your Apple Account in Xcode and select your signing Team. The default bundle identifier is `cn.gd306.tideenglish.ios`; if unavailable, override it with your own unique identifier in the local signing configuration. See the [iPhone guide](docs/guides/iphone.md).

### Android

Prepare JDK 17, Android SDK Platform 36 and Build Tools 35.0.0, then set `JAVA_HOME` and `ANDROID_HOME`:

```sh
cd mobile/android
./gradlew :app:assembleDebug
```

The APK is written to `mobile/android/app/build/outputs/apk/debug/app-debug.apk`. The application ID is `cn.gd306.tideenglish.android`. See the [Android guide](docs/guides/android.md).

### Models and accounts

Choose your learning and explanation languages in the app, then enter your own key in **Settings → Model & API key**. Never put keys in source files, logs or chat. Credentials are stored separately for each provider and custom endpoint; changing the recipient requires renewed consent. See [Models and voice](docs/guides/models-and-voice.md).

Email identity is optional. Clients retain the email-account contract at `https://api.gd306.cn`; this project rebuild did not deploy or modify that live service. See the [account service guide](docs/operations/accounts.md) for self-hosting. Email identity and the hosted gateway are separate components.

## Verification and development

```sh
python3 -m unittest discover -s tools/tests -t .
python3 tools/export_android_content.py --check
python3 tools/check_cross_platform.py
swift test --package-path mobile/ios
```

See [Build and test](docs/development/build-and-test.md) for complete commands and the [verification record](docs/development/verification.md) for actual results and limitations. Changes to shared teaching logic must keep Swift, Kotlin and contract checks aligned.

## Independent identity and learning data

This project uses independent application identifiers and does not automatically read another installation's sandbox or credentials. The project rebuild did not uninstall apps, clear existing data or modify production databases. To migrate learning records, export a backup from the original app and manually import it into the new app; enter model keys again. Do not uninstall an existing app to resolve a signing mismatch.

Release templates, sample products and prices do not establish that this app is published or ready to accept payments. Before release, configure your own signing, store application and backend. Keep commercial features disabled until separately verified.

Website, support, privacy and terms links use reserved `.example` domains as release configuration examples and are not deployed. Replace them with pages you actually provide before public release. These example addresses are not used for model requests or the current email sign-in service.

## License

[MIT License](LICENSE), with original copyright and third-party attribution retained. See [NOTICE](NOTICE) for provenance, [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and [SECURITY.md](SECURITY.md) for security handling.
