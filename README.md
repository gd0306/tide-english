# Tide English

**English** | [简体中文](README-CN.md)

A native language-learning app for practising expression, comprehension and vocabulary through natural conversation. The project includes a SwiftUI iOS client, a Jetpack Compose Android client and a separate email account service.

Tide English uses your own model API key by default. Learning records stay on your device, and signing in is optional. Hosted voice, trials and purchases are disabled by default. This repository contains the full source and pinned dependencies, without user credentials, personal signing settings or historical build artifacts.

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

Open or attach this project directory in your agent, then send it the entire prompt below. It covers both iPhone and Android. The agent needs access to your local files, terminal and connected device. Complete Apple Account sign-in, system password entry, device trust and permission prompts yourself in the system UI; never send credentials or passwords in chat.

```text
Build, install and launch the current Tide English project on my connected phone. Continue until the task is complete; do not stop at instructions or a generated installation package.

The source is the currently opened or attached tide-english directory. First confirm that README.md, mobile/ios, mobile/android and tools/generate_project.py exist. If this environment cannot access the source or locate the project, ask only for the actual source directory or repository address; do not invent a download URL. Determine whether a remote exists from the actual output of git remote -v.

Execution requirements:
1. Read AGENTS.md, README.md or README-CN.md, docs/development/build-and-test.md, and the target platform's docs/guides/iphone.md or docs/guides/android.md. Inspect and preserve existing changes. Use pinned dependencies; do not reset the repository, upgrade dependencies or refactor unrelated features.
2. Detect the host OS, development tools and connected physical phones, distinguishing phones from simulators and emulators. Use the phone if exactly one is connected. If none is connected, authorization is missing, or multiple devices make the target ambiguous, tell me exactly what to connect, unlock, authorize or select. Explicitly target every installation command. Do not install on another phone or describe a simulator result as a successful phone installation.
3. I authorize the normal tool checks, dependency resolution, tests, builds, signing, installation and launch needed for this task; do not repeatedly ask whether to continue. Follow your agent's permission rules. If system approval, account sign-in or essential information is required, explain the blocker and the action I need to take, then resume. Never ask me for a system password, Apple verification code, model API key or email authorization code.

iPhone workflow:
4. Build on macOS with Xcode. Check the Xcode version, developer directory, first-launch status, iOS SDK and device support. Read tools/generate_project.py and use mobile/ios/TideEnglish.xcodeproj with the TideEnglish scheme. Prefer building the existing project directly. Run the generator only if the project is missing or its references need updating; first preserve project changes and save existing Team and identifier overrides in the ignored Configuration/Local.xcconfig so regeneration cannot lose signing settings. Resolve pinned packages, run the Swift core tests and build for iOS Simulator. Prefer offline operation when caches are complete, and use normal code signing.
5. Inspect the current Team, bundle identifier and installation state on the target phone. For a first installation, start with cn.gd306.tideenglish.ios and configure a unique identifier if it is unavailable. Guide me through Apple Account or Team selection in Xcode when needed. For updates to the same app, preserve the existing Team, identifier and signing identity. Store local overrides in the ignored mobile/ios/Configuration/Local.xcconfig; never commit personal signing settings or private keys.
6. Build for the physical target using the configured Team, then install and launch through Xcode or the local xcrun devicectl. Consult the installed tool's --help for command arguments. Clearly identify where I need to unlock the phone, trust this computer, enable Developer Mode, trust a developer profile or approve a system prompt. Report the provisioning profile expiry from the build artifact. Do not export signing private keys or read model credentials.

Android workflow:
7. Check JDK 17, Android SDK Platform 36, Build Tools 35.0.0 and adb. Configure local JAVA_HOME, ANDROID_HOME or the ignored local.properties as needed. Detect devices with adb devices -l. If unauthorized, ask me to unlock the phone and approve USB debugging; if offline, restore the connection without clearing phone data.
8. In mobile/android, resolve pinned dependencies with the repository's Gradle Wrapper and run :app:testDebugUnitTest, :app:lintDebug and :app:assembleDebug. The default application ID is cn.gd306.tideenglish.android. Use local debug signing for a first installation and matching signing credentials when updating an existing installation. Verify the final APK's identifier, signature and personal-build flags, then install with adb -s TARGET_SERIAL install -r and launch the main Activity. Do not uninstall, clear data, force a downgrade or silently change the identifier to resolve a signature or version conflict. If signing cannot be matched, preserve the installed app and report the specific reason.

Requirements for both platforms:
9. Preserve installed apps, learning records and credentials. If a same-name older app has a different application identifier, retain it as a separate installation; do not overwrite it or migrate its data automatically. I can manually export and import learning backups. Do not read, export or log model credentials, account tokens or personal learning content from the device.
10. Keep hosted services, trials, purchases and learning-data cloud sync disabled. Do not deploy backend services, modify production databases, send verification emails or initiate real model requests or voice calls. Optional email sign-in must not be a prerequisite for local learning. After installation, I will choose my learning, explanation and interface languages and enter my own key in Settings → Model & API key.
11. Confirm installation and launch with device tools. Report the target phone, application identifier and version, which test/build/signing/install/launch checks passed, artifact paths, iOS signing expiry if available, and any actions still needed on the phone. Report failures and blockers accurately; a successful compile alone does not mean the app was installed. I will start the first real conversation myself.
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
