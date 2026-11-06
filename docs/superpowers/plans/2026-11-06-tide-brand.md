# Tide Brand Implementation Plan

**Goal:** Rename the public brand to Tide / 潮语 and the existing GitHub repository to tide.

**Architecture:** Change display copy and repository links together. Retain TideEnglish modules, TIDE_ENGLISH build settings, cn.gd306.tideenglish application identities, storage paths, archive formats, service names and configured sender identities for compatibility.

**Tech Stack:** SwiftUI, Kotlin/Compose, Python build tools, TypeScript gateway.

**Spec:** User-approved conversation: App Tide, Chinese name 潮语, repository tide; existing stable identities remain compatible.

## Tasks

- [x] Update public copy, Chinese translations, launcher labels, documentation and repository links. Preserve licenses and third-party notices.
- [x] Generate Xcode resources with tools/generate_project.py; add identity coverage for new display labels and retained storage identities.
- [x] Run Python tests, content export parity, cross-platform checks, Swift tests, affected server checks and Android build/tests where toolchains are available.
- [x] Rename the existing GitHub repository through its settings, verify star preservation, and update origin. Do not create a replacement repository or deploy services.

## Verification record

- GitHub: `gd0306/tide`, repository ID `1430553159` unchanged, 21 stars before and after; old URL returns HTTP 301 to the new URL. Origin updated.
- Python: 93 tests passed; content export and cross-platform checks passed.
- Swift: 390 tests passed. Xcode Debug simulator build passed for both architectures. Built Info.plist retains `cn.gd306.tideenglish.ios`; English and Simplified Chinese display-name resources contain Tide and 潮语.
- Gateway: TypeScript check passed; 140 tests passed, 393 PostgreSQL-dependent tests skipped without TEST_DATABASE_URL.
- Accounts: both configuration/SMTP fixture tests passed. Database integration suite requires ACCOUNTS_TEST_DATABASE_URL naming a test database and was not run successfully here.
- Android: final validation passed with temporary Java 17: 460 unit tests, lintDebug, assembleDebug and assembleUiTestAndroidTest. APK labels verified as Tide / 潮语 and application ID remains cn.gd306.tideenglish.android. System Java 8 is too old and IntelliJ's Java 25 is incompatible with current Gradle.
- Initial offline phase did not install on devices, deploy services or push source. Existing public screenshots and historical verification records retain their original capture state.
- Legacy TideEnglish module/build names, application IDs, learning-data paths, sender identity validation, example service domains and deployment identities are intentionally retained for compatibility.

- Independent review: corrected Chinese dynamic-brand captures and optional Android account heading; follow-up review found no remaining actionable capture-slot issues. Provider identities, endpoints and unknown input remain protected by existing localization fallback behavior.

## Follow-up authorized by user

- [x] Audit README publication: local files were updated but not committed/pushed; GitHub still showed the prior README. Clarified brand-versus-internal-name compatibility in both READMEs and marked historical design/screenshots as historical.
- [x] Back up the connected iPhone 17 installation, retain its existing local signing/application identity, and cover-install Release 1.0 (11) without uninstalling.
- [x] Run the physical-device brand/settings/vocabulary/themes smoke test: one test passed; normal launch succeeded. Full stored archive payloads (49 sessions) and preferences are unchanged after update. Device archives, signing details and screenshots remain ignored under .build/tide-brand-device.
Publication is authorized after successful hardware checks: commit and push the verified source to origin/main, then verify the online English/Chinese README content.

Android hardware was not connected. No live model/voice call or server deployment was needed for this rename.
