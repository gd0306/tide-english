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

    def test_new_identity_and_personal_defaults(self):
        gradle = (ROOT / 'mobile/android/app/build.gradle.kts').read_text()
        self.assertIn('namespace = "cn.gd306.tideenglish"', gradle)
        self.assertIn('applicationId = "cn.gd306.tideenglish.android"', gradle)
        swift = (ROOT / 'mobile/ios/Package.swift').read_text()
        self.assertIn('name: "TideEnglishCore"', swift)


if __name__ == '__main__':
    unittest.main()
