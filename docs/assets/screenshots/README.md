# README screenshots

Captured on 23 October 2026 from the current Tide English iOS simulator build, version 1.0 (1), using a dedicated iPhone 17 simulator running iOS 27.0.

| Directory | Interface | Theme | Screens |
| --- | --- | --- | --- |
| `ios/en/` | English | Paper | Conversation, themes, bilingual vocabulary, settings |
| `ios/zh-CN/` | Chinese | Midnight | Conversation, themes, bilingual vocabulary, settings |

These are unedited captures of the native application. Conversation and theme examples use Spanish learning with English explanations. Vocabulary examples use English learning with Simplified Chinese definitions. All content comes from the app's existing offline preview fixtures, with an in-memory learning store and preview account state. The speaking indicator is a simulated UI state; no microphone recording, live model call, real credential or personal learning record was used.

The images demonstrate the iOS interface. They do not represent Android screenshots or a new live voice verification.

## Reproduce

Build a Debug simulator application using [the build guide](../../development/build-and-test.md). Create and boot a dedicated iPhone simulator, then install `.build/ios/Build/Products/Debug-iphonesimulator/TideEnglish.app` using `xcrun simctl install`. Always explicitly name your dedicated simulator UUID so other simulators and phones remain unchanged.

Launch `cn.gd306.tideenglish.ios` with these arguments:

```text
--preview
--preview-provider=deepSeek
--preview-email-account
--preview-interface-language=english
--preview-interface-theme=paper
--screenshot=conversation
```

Use `themes`, `words` or `settings` for the other `--screenshot` values. Add `--preview-vocabulary` for the words screen to populate the English/Chinese definition fixtures. For Chinese captures, use `--preview-interface-language=chinese` and `--preview-interface-theme=midnight`.

Normalize the dedicated simulator's status bar with `xcrun simctl status_bar ... override` if desired. Wait until startup, sheet animations and preview definitions have finished rendering, then capture with `xcrun simctl io ... screenshot`. Inspect each image before updating the README, and shut down your dedicated simulator afterward.

Images remain at their native 1206 × 2622 resolution. The README scales them for display and links to the full-size PNGs. File sizes and SHA-256 values are recorded in [manifest.json](manifest.json).
