# Tide for Android

Native Kotlin and Jetpack Compose client for Android 8.0 or later. The personal Tide build includes the customized iOS provider selection, theme and interface-language settings, bilingual vocabulary definitions, local learning/history, compatible JSON backups and optional email-code accounts.

Settings has one **Model & API key** entry for OpenAI, DeepSeek, GLM, Gemini and Custom HTTPS services. Each provider and Custom endpoint has a separate encrypted key. All conversation text, meanings, explanations and assessments use the selected provider and chat model. Changing the model or recipient requires renewed AI consent. Enter keys inside the app only; they never belong in Gradle, source files, logs or learning exports.

OpenAI keeps native WebRTC voice. GLM and Gemini have native WebSocket voice; explicit unsupported-capability responses permit a same-provider device-voice fallback. DeepSeek and Custom use on-device recognition, the selected chat model and an offline system reading voice. This fallback requires available Android 12+ on-device recognition; unsupported devices keep typing. Native voice models are separate from the editable chat model, as on iOS. Background native calls retain an ongoing notification; device-voice calls end when backgrounded.

Gemini currently ends cleanly and asks you to reconnect if Google sends a native-session expiry (`goAway`); automatic session resumption is not implemented in this Android port. Real microphone, Bluetooth routing and provider-account access need checking on the learner's actual phone.

Word taps in all eleven languages open a contextual meaning sheet, matching the iOS flow. Mandarin uses a bundled offline phrase dictionary with an ICU fallback; unresolved common ambiguous readings retain their source characters.

Choose **English / 中文** and **Paper / Midnight / Grove** in Settings. Learning and meaning languages stay independent. Word cards and details show definitions in both selected languages. Missing definitions have an explicit load/retry action; downloaded definitions remain available offline. The original English sense is labelled as a reference when bilingual definitions are absent.

Email-code sign-in is disabled by default: no account entry is shown and no account session is restored. To enable it, configure your own compatible account service and set both `TIDE_ENGLISH_EMAIL_ACCOUNTS_ENABLED=true` and `TIDE_ENGLISH_EMAIL_ACCOUNT_API_URL=https://accounts.example.test` in ignored `local.properties` (replace the example URL with your service). Google/Apple sign-in, hosted AI, trials and purchases remain separate opt-ins. Email identity does not sync learning records; signing out or deleting it preserves learning data and model keys.

See the root [development guide](../../docs/development/build-and-test.md).

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

Requirements: Java 17, Android SDK 36 and Build Tools 35.0.0. The API key is entered inside the app and must never be configured in Gradle. `local.properties`, private signing keys and build outputs are excluded from Git.
