# Changelog

## 0.1.7

### validate command improvements
- Added checks for: `id` vs `id_suffix` mutual exclusion, `firebase.file` vs `project_id` mutual exclusion, `firebase.file` on iOS, store fields on wrong platform, `google_play.priority` range (1–5), Android-only build_type fields on iOS
- Added warnings for: missing signing credentials when release is configured, neither `id` nor `id_suffix` set
- Full error and warning reference documented in `docs/flutter/cli-commands.md`

## 0.1.6

- Version bump across all plugins (gradle 2.0.5, cocoapods 0.1.4, fastlane 0.1.11, studio 1.0.5)
- Workflow: resolve-versions now syncs README install snippets and studio flavorize fallback version
- Workflow: switched to ANNTECH_PAT for tag creation (fixes 403 from org-restricted GITHUB_TOKEN)

## 0.1.5

### pub.dev quality improvements
- `AnnFlavor.init()` no longer requires `buildType:` — build type is now derived automatically from Dart compile-time constants (`dart.vm.product` / `dart.vm.profile`); no `--dart-define` needed
- Full dartdoc coverage on all public API classes and members: `AnnFlavor`, `AnnFlavorConfig`, `AnnPlatform`, `AnnAuthConfig`, `AnnCustomGroup`
- Added `example/` — runnable Flutter app demonstrating `AnnFlavor.init`, `custom()` with RevenueCat, and all runtime getters
- Package now declares support for all platforms: Android, iOS, macOS, Web, Linux, Windows
- Added `topics` to pubspec: `flutter`, `flavor`, `build-configuration`, `firebase`, `codegen`

## 0.1.4

### Custom attributes
- New `custom:` block in `annspec.yaml` — define named groups of typed key-value data at `default:`, `flavor:`, or `build_types:` level on any platform (Android, iOS, web, Windows)
- 4-level cascade with deep merge: `default → default.buildType → flavor → flavor.buildType`
- Dart codegen: generates a `custom(String group)` override in each flavor class; values are pre-resolved per build type at sync time — no runtime YAML parsing
- New runtime class `AnnCustomGroup` — typed accessors: `string()`, `boolean()`, `integer()`, `decimal()`, `strings()`, raw `[]` operator, and `keys`
- `AnnFlavor.init()` gains a `buildType` parameter (defaults to `'release'`); `AnnFlavor.buildType` getter added
- Base `AnnFlavorConfig.custom()` now has a default implementation returning `null` — existing subclasses compile unchanged

### Android
- Per-flavor `AndroidManifest.xml` generation — creates manifest if missing
- AdMob meta-data injection (`com.google.android.gms.ads.APPLICATION_ID` + GMS version) when `admob.gms_ads_id` is set on the flavor
- `settings.gradle.kts` and `app/build.gradle.kts` injections now placed at end of their respective blocks
- Injected lines preceded by `// Added by ann_flutter_flavor` comment

### iOS
- Per-flavor xcconfig generation — creates `ios/Flutter/<Flavor>Debug.xcconfig` and `ios/Flutter/<Flavor>Release.xcconfig` per flavor; patches existing files to add missing variables
- xcconfig variables: `PRODUCT_BUNDLE_IDENTIFIER`, `APP_NAME`, `FLUTTER_BUILD_NAME`, `FLUTTER_BUILD_NUMBER`, `GAD_APPLICATION_IDENTIFIER` (when `admob:` is set)
- `Info.plist` patching — replaces hardcoded values with `$(VARIABLE)` references for bundle ID, display name, version, build number, and AdMob ID

### AdMob YAML structure
- `gms_ads_id` is now nested under an `admob:` block at default, flavor, and build_type levels
- Presence of `admob:` implies AdMob is enabled — no separate `admob_enabled` flag
- `admob.gms_ads_id` is not exposed in the generated Dart runtime API — the native SDK reads it from the manifest/plist automatically

## 0.1.0

- Initial release
- CLI `sync` command: generates `ann_flavor.g.dart` from `annspec.yaml`
- CLI `validate` command: validates spec for missing required fields
- Android wiring: patches `settings.gradle.kts` and `app/build.gradle.kts`
- iOS wiring: patches `Podfile` with CocoaPods plugin reference
- Runtime API: `AnnFlavor`, `AnnFlavorConfig`, `AnnPlatform`, `AnnSubscription`, `AnnAuthConfig`
