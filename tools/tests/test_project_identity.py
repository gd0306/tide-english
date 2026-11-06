"""Independent project identity and source-layout regression checks."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProjectIdentityTests(unittest.TestCase):
    def test_native_and_server_entry_points_exist(self):
        for relative in (
            'mobile/ios/TideEnglish.xcodeproj/project.pbxproj',
            'mobile/ios/Package.swift',
            'mobile/ios/Application/TideEnglishApp.swift',
            'mobile/android/app/src/main/java/cn/gd306/tideenglish/TideEnglishViewModel.kt',
            'server/gateway/package.json', 'server/accounts/package.json',
            'packages/contracts/minute-balance.schema.json',
        ):
            with self.subTest(path=relative):
                self.assertTrue((ROOT / relative).is_file(), relative)

    def test_no_previous_brand_in_source_paths_or_text(self):
        old = 'mu' + 'ral'
        for file in ROOT.rglob('*'):
            relative = file.relative_to(ROOT)
            if any(part.startswith('.') or part in ('node_modules', 'build', '__pycache__') for part in relative.parts):
                continue
            self.assertNotIn(old, str(relative).lower())
            if not file.is_file():
                continue
            try:
                text = file.read_text()
            except (UnicodeError, ValueError):
                continue
            self.assertNotIn(old, text.lower(), str(relative))

    def test_public_brand_and_stable_learning_identity(self):
        import plistlib
        import xml.etree.ElementTree as ET
        info = plistlib.loads((ROOT / 'mobile/ios/Application/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], 'Tide')
        for locale, label in [('en', 'Tide'), ('zh-Hans', '潮语')]:
            self.assertIn(f'"CFBundleDisplayName" = "{label}";',
                          (ROOT / f'mobile/ios/Application/{locale}.lproj/InfoPlist.strings').read_text())
        for locale, label in [('values', 'Tide'), ('values-es', 'Tide'), ('values-zh', '潮语')]:
            strings = ET.parse(ROOT / f'mobile/android/app/src/main/res/{locale}/strings.xml')
            self.assertEqual(strings.find("string[@name='app_name']").text, label)
        manifest = ET.parse(ROOT / 'mobile/android/app/src/main/AndroidManifest.xml')
        self.assertEqual(manifest.find('application').get('{http://schemas.android.com/apk/res/android}label'), '@string/app_name')
        storage = (ROOT / 'mobile/ios/Application/Storage.swift').read_text()
        self.assertEqual(storage.count('.appendingPathComponent("Tide English", isDirectory: true)'), 2)
        project = (ROOT / 'mobile/ios/TideEnglish.xcodeproj/project.pbxproj').read_text()
        self.assertIn('Application/zh-Hans.lproj/InfoPlist.strings', project)
        self.assertIn('cn.gd306.tideenglish.ios', project)

    def test_new_identity_and_personal_defaults(self):
        gradle = (ROOT / 'mobile/android/app/build.gradle.kts').read_text()
        self.assertIn('namespace = "cn.gd306.tideenglish"', gradle)
        self.assertIn('applicationId = "cn.gd306.tideenglish.android"', gradle)
        swift = (ROOT / 'mobile/ios/Package.swift').read_text()
        self.assertIn('name: "TideEnglishCore"', swift)


if __name__ == '__main__':
    unittest.main()
