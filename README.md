# ann_flutter_flavor

A CLI tool and runtime API for ANN Flutter flavor management.

Reads a single `annspec.yaml` source-of-truth and:
- Generates typed Dart flavor code (`lib/generated/ann_flavor.g.dart`)
- Generates Firebase configuration scripts
- Wires the Gradle plugin into Android build files (`settings.gradle.kts`, `app/build.gradle.kts`)
- Generates per-flavor Android manifests with AdMob meta-data when configured
- Generates per-flavor iOS xcconfig files and patches `Info.plist` with variable references
- Wires the CocoaPods plugin into the iOS `Podfile`

---

## Installation

Add to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  ann_flutter_flavor: ^0.4.1
```

---

## IDE Plugin

The **ANN Flutter Flavor** plugin for Android Studio and IntelliJ IDEA lets you author and validate `annspec.yaml` visually.

- Guided form UI for flavors, Firebase config, RevenueCat subscriptions, Google Sign-In keys, and AdMob IDs
- Spec validation highlights missing or invalid fields before you sync
- One-click sync via **Tools → ANN Tools → Sync Spec**

**Install:** Android Studio → Settings → Plugins → Marketplace → search **"ANN Flutter Flavor"**

> Plugin ID: `dev.anntech.studio.flavorize`

---

## annspec.yaml format

```yaml
app:

  integrations:
    firebase: true   # enable flutterfire configure during sync

  android:
    sdk:
      minSdk: 23
      compileSdk: 35
      targetSdk: 35
    default:
      id: com.example.myapp
      name: "My App"
      version_name: 1.0.0
      version_code: 10000
      admob:                                      # optional — enables AdMob for all flavors
        gms_ads_id: "ca-app-pub-XXXX~XXXXXXXXXX"
      build_types:
        release:
          firebase:
            project_id: "my-firebase-prod"
            service_account: "keys/flutterfire-sa.json"   # required for project_id mode
          auth:
            clientId: "000000000000-release.apps.googleusercontent.com"
            reversedClientId: "com.googleusercontent.apps.000000000000-release"
        debug:
          firebase:
            project_id: "my-firebase-dev"
            service_account: "keys/flutterfire-sa.json"
      custom:                                       # default-level custom attributes
        revenuecat:
          api_key: "rc_default_key"
          entitlement_ids:
            - standard
        analytics:
          enabled: true
    flavor:
      free:
        id_suffix: .free
        name: "My App Free"
        main_file: "lib/flavors/main_free.dart"
        admob:                                    # flavor-level override
          gms_ads_id: "ca-app-pub-YYYY~YYYYYYYYYY"
        custom:
          revenuecat:
            api_key: "goog_XXXX"
            entitlement_ids: ["standard"]
        custom:
          revenuecat:
            api_key: "rc_free_key"               # overrides default; entitlement_ids falls through
        build_types:
          debug:
            custom:
              revenuecat:
                api_key: "rc_free_debug_key"     # overrides free.release for debug builds
      pro:
        id_suffix: .pro
        name: "My App Pro"
        main_file: "lib/flavors/main_pro.dart"
        custom:
          revenuecat:
            api_key: "rc_pro_key"
            entitlement_ids:
              - standard
              - premium

  ios:
    default:
      id: com.example.myapp
      name: "My App"
      version_name: 1.0.0
      version_code: 10000
      team_id: "YOURTEAMID"
      admob:                                      # optional — shared AdMob ID for iOS
        gms_ads_id: "ca-app-pub-XXXX~XXXXXXXXXX"
    flavor:
      free:
        id_suffix: .free
        name: "My App Free"
        main_file: "lib/flavors/main_free.dart"
      pro:
        id_suffix: .pro
        name: "My App Pro"
        main_file: "lib/flavors/main_pro.dart"
```

### admob field cascade

`admob.gms_ads_id` resolves in priority order: **build_type → flavor → default**.

- Set it once under `default:` to share one AdMob App ID across all flavors
- Override under a specific `flavor:` to use a different ID for that flavor
- Override under `flavor.build_types.<bt>:` for build-type-level control
- **Presence of `admob:` enables AdMob** — no separate `admob_enabled` flag needed

AdMob is only applicable to **Android** and **iOS**. Web and Windows have no AdMob support.

---

## Firebase Setup

### `config_file` vs `project_id`

Firebase configuration uses two different modes depending on the platform:

| Platform | Mode | Field | What happens at sync |
|----------|------|-------|----------------------|
| Android | Static file | `config_file` | Copies `google-services.json` to the correct source set |
| iOS | Dynamic fetch | `project_id` | Runs `flutterfire configure`; generates `firebase_options.dart` |
| Web | Dynamic fetch | `project_id` | Runs `flutterfire configure`; generates `firebase_options.dart` |

Do **not** set `config_file` on iOS — sync will abort with an error. Do **not** set
`project_id` on Android — only `config_file` is used there.

### Android: cascade destinations

`google-services.json` is copied to a destination that matches the cascade level at which
`config_file` is resolved. Android's Gradle plugin reads from the most-specific path it
finds:

| Cascade level | `google-services.json` destination |
|---------------|-------------------------------------|
| `flavor.build_types.<bt>.firebase.config_file` | `android/app/src/{flavor}{BuildType}/google-services.json` |
| `flavor.build_types.*.firebase.config_file` | `android/app/src/{flavor}/google-services.json` |
| `default.build_types.<bt>.firebase.config_file` | `android/app/src/{buildType}/google-services.json` |
| `default.build_types.*.firebase.config_file` | `android/app/google-services.json` |

Example — a single shared `google-services.json` for all flavors and build types:

```yaml
android:
  default:
    build_types:
      release:
        firebase:
          config_file: "keys/firebase/google-services.json"
      debug:
        firebase:
          config_file: "keys/firebase/google-services-dev.json"
```

### iOS: why no `GoogleService-Info.plist` is needed

In `project_id` mode, `dart run ann_flutter_flavor sync` runs `flutterfire configure`
which generates per-flavor, per-build-type Dart options files:

```
lib/generated/firebase/{flavor}_{buildType}_ios_firebase_options.dart
```

The CocoaPods plugin (`ann-flavor-cocoapods`) reads these files during `pod install` and
injects `GOOGLE_APP_ID` directly into Xcode build settings. A static
`GoogleService-Info.plist` in `ios/Runner/` is **not needed** and may cause stale config
if left in place alongside the generated files.

### Service account setup

`flutterfire configure` requires authentication. The only supported auth method is a
Firebase service account JSON — no `firebase login`, `gcloud auth`, or ADC.

**Generate the service account:**
1. Firebase Console → Project Settings → Service accounts
2. Click **Generate new private key** → download JSON
3. Store the JSON securely (do not commit it)

**annspec.yaml reference:**

```yaml
ios:
  default:
    build_types:
      release:
        firebase:
          project_id: "my-firebase-prod"
          service_account: "keys/firebase-sa.json"   # path relative to project root
      debug:
        firebase:
          project_id: "my-firebase-dev"
          service_account: "keys/firebase-sa-dev.json"
```

**CI/CD (GitHub Actions) — decode from a base64 secret:**

```yaml
- name: Decode Firebase service account
  run: |
    echo "${{ secrets.FIREBASE_SA_JSON_BASE64 }}" | base64 --decode > keys/firebase-sa.json

- name: Sync spec
  run: dart run ann_flutter_flavor sync
```

Encode once locally: `base64 -i firebase-sa.json | pbcopy` then paste as the secret value.

---

## CLI Commands

### sync

```bash
dart run ann_flutter_flavor sync
dart run ann_flutter_flavor sync -p ../my_flutter_app
dart run ann_flutter_flavor sync --format json              # machine-readable pre-flight result
dart run ann_flutter_flavor sync --firebase-mode script     # generate firebase.sh instead of running flutterfire
```

Validates `annspec.yaml` first (Step 0). If there are errors, sync aborts and no files
are written. Warnings are printed but generation continues.

Step order: `[0/6]` validate → `[1/6]` Dart → `[2/6]` Android → `[3/6]` iOS →
`[4/6]` Firebase → `[5/6]` Fastlane → `[6/6]` Melos.

**`--firebase-mode script`** — writes `lib/generated/scripts/firebase.sh` containing
all the `flutterfire configure` commands instead of executing them. Use this when
Firebase auth is not available during sync (e.g. CI environments where the service
account is injected in a later step):

```bash
# Sync everything except Firebase:
dart run ann_flutter_flavor sync --firebase-mode script

# Later, when auth is ready:
bash lib/generated/scripts/firebase.sh
```

The generated script navigates to the project root automatically and uses paths relative
to that root — it can be run from any directory.

What it generates / patches:

| File | Description |
|------|-------------|
| `lib/generated/ann_flavor.g.dart` | Typed `AnnFlavorConfig` subclass per flavor |
| `lib/generated/firebase_options_*.dart` | Generated by `flutterfire configure` for `project_id` build types |
| `fastlane/Fastfile` + `fastlane_*.rb` | CI/CD lanes per platform |
| `android/settings.gradle.kts` | Patches `mavenCentral()` + ANN plugin declaration |
| `android/app/build.gradle.kts` | Patches `id("dev.anntech.flavorize")` |
| `android/app/src/<flavor>/AndroidManifest.xml` | Per-flavor manifest; GMS Ads meta-data if `admob:` set |
| `ios/Flutter/<Flavor>Debug.xcconfig` | Per-flavor debug xcconfig |
| `ios/Flutter/<Flavor>Release.xcconfig` | Per-flavor release xcconfig |
| `ios/Runner/Info.plist` | Patches keys to use `$(VARIABLE)` references |
| `ios/Podfile` | Patches in CocoaPods plugin reference |

### validate

```bash
dart run ann_flutter_flavor validate
dart run ann_flutter_flavor validate -p ../my_flutter_app
dart run ann_flutter_flavor validate --format json
```

Checks `annspec.yaml` for errors and warnings without writing any files. Useful in CI.

### doctor

```bash
dart run ann_flutter_flavor doctor
dart run ann_flutter_flavor doctor -p ../my_flutter_app
```

Shows the `ann_flutter_flavor` version and checks each linked plugin's installed version
against the expected target version. Exits 1 if any plugin is outdated.

---

## Runtime API

### Initialise in each flavor entry point

```dart
// lib/flavors/main_free.dart
import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:my_app/generated/ann_flavor.g.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AnnFlavor.init(
    config:   FreeFlavor(),
    platform: Platform.isAndroid ? AnnPlatform.android
            : Platform.isIOS    ? AnnPlatform.ios
            : AnnPlatform.web,
  );

  runApp(const MyApp());
}
```

`AnnFlavor.buildType` is derived automatically from Flutter's `kDebugMode` / `kReleaseMode` —
no `--dart-define` needed.

### Access flavor data anywhere

```dart
AnnFlavor.key                                       // "free"
AnnFlavor.current.name                              // "My App Free"
AnnFlavor.current.androidId                         // "com.example.myapp.free"
AnnFlavor.current.iosId                             // "com.example.myapp.free"
AnnFlavor.platform                                  // AnnPlatform.android
AnnFlavor.buildType                                 // "release" or "debug"

// RevenueCat subscriptions
final subs = AnnFlavor.current.subscriptions(AnnFlavor.platform);
subs?.first.apiKey                                  // "goog_XXXX"
subs?.first.entitlementIds                          // ["standard"]

// Google Sign-In
final auth = AnnFlavor.current.auth(AnnFlavor.platform);
auth?.clientId                                      // release client ID
final authDebug = AnnFlavor.current.authDebug(AnnFlavor.platform);
authDebug?.clientId                                 // debug client ID

// Custom attributes — resolves cascade + build type automatically
AnnFlavor.current.custom('revenuecat')?.string('api_key')
AnnFlavor.current.custom('revenuecat')?.strings('entitlement_ids')
AnnFlavor.current.custom('analytics')?.boolean('enabled')
```

> **AdMob:** The AdMob App ID is injected natively into `AndroidManifest.xml` and
> `Info.plist` by the `sync` command. The AdMob SDK reads it automatically — just call
> `MobileAds.instance.initialize()`. No Dart API needed.

### Custom attributes reference

| Accessor | YAML type | Returns |
|----------|-----------|---------|
| `string(key)` | quoted string | `String?` |
| `boolean(key)` | `true` / `false` | `bool?` |
| `integer(key)` | integer number | `int?` |
| `decimal(key)` | decimal number | `double?` |
| `strings(key)` | YAML list | `List<String>?` |
| `[key]` | any | `dynamic` |

All accessors return `null` if the group doesn't exist or the key is missing.
See [docs/custom-attributes.md](../../docs/custom-attributes.md) for the full cascade rules.

### API reference

| Symbol | Description |
|--------|-------------|
| `AnnFlavor.init(config:, platform:)` | Initialise once at app startup |
| `AnnFlavor.current` | Active `AnnFlavorConfig` — throws if not initialised |
| `AnnFlavor.platform` | Active `AnnPlatform` — throws if not initialised |
| `AnnFlavor.key` | Shorthand for `AnnFlavor.current.key` |
| `AnnFlavorConfig.key` | Flavor key string (e.g. `"free"`) |
| `AnnFlavorConfig.name` | Display name |
| `AnnFlavorConfig.androidId` | Full Android bundle ID |
| `AnnFlavorConfig.iosId` | Full iOS bundle ID |
| `AnnFlavorConfig.subscriptions(platform)` | List of `AnnSubscription` or null |
| `AnnFlavorConfig.auth(platform)` | Release `AnnAuthConfig` or null |
| `AnnFlavorConfig.authDebug(platform)` | Debug `AnnAuthConfig` or null |
| `AnnPlatform` | `android`, `ios`, `web`, `windows` |
| `AnnSubscription` | `apiKey` + `entitlementIds` |
| `AnnAuthConfig` | `clientId` + `reversedClientId` |

---

## Build commands

```bash
flutter run   --flavor free -t lib/flavors/main_free.dart
flutter run   --flavor pro  -t lib/flavors/main_pro.dart
flutter build apk       --flavor free -t lib/flavors/main_free.dart
flutter build appbundle --flavor pro  -t lib/flavors/main_pro.dart
flutter build ipa       --flavor free -t lib/flavors/main_free.dart
```

---

## License

MIT
