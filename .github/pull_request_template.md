## Summary

<!-- What changed and why. -->

## Checklist

- [ ] Describes the user-visible change, or states there is none.
- [ ] Says how it was verified (device/simulator, or why that wasn't possible).
- [ ] A change under `mobile/ios/Domain/` has the matching change under `mobile/android/app/src/main/java/cn/gd306/tideenglish/core/`, verified with `python3 tools/check_cross_platform.py`.
- [ ] Fixtures under `packages/fixtures/cross-platform/` are updated if shared behavior changed.
- [ ] Notes any remaining limitations.
