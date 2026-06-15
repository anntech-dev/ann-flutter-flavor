# ann_flutter_flavor

A CLI tool and runtime API for ANN Flutter flavor management.

Reads a single `annspec.yaml` source-of-truth and:
- Generates typed Dart flavor code (`ann_flavor.g.dart`)
- Wires the Gradle plugin reference into Android build files
- Wires the CocoaPods plugin reference into the iOS Podfile

---

## Installation

Add to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  ann_flutter_flavor: ^0.1.0
```

---

## IDE Plugin

The **ANN Flutter Flavor** plugin for Android Studio and IntelliJ IDEA lets you author and validate `annspec.yaml` visually — no need to write YAML by hand.

- **Guided form UI** for flavors, Firebase config, RevenueCat subscriptions, and Google Sign-In keys
- **Spec validation** highlights missing or invalid fields before you sync
- **One-click sync** via Tools → ANN Tools → Sync Spec, which calls this package under the hood

**Install:** Open Android Studio → Settings → Plugins → Marketplace → search **"ANN Flutter Flavor"**

> Plugin ID: `dev.anntech.studio.flavorize`  
> Source: [github.com/anntech-dev/android-studio-plugins](https://github.com/anntech-dev/android-studio-plugins)

Once the plugin generates your `annspec.yaml`, run `dart run ann_flutter_flavor sync` to produce the Dart code and wire Android/iOS.

---

## Setup

### 1. Create `annspec.yaml` at the root of your Flutter project

```yaml
platforms:
  android:
    base_id: com.example
    flavors:
      - key: my_app
        name: My App
        id_suffix: .myapp
        subscriptions:
          - api_key: goog_XXXX
            entitlement_ids: [standard, premium]

  ios:
    base_id: com.example
    flavors:
      - key: my_app
        name: My App
        id_suffix: .myapp
        subscriptions:
          - api_key: appl_XXXX
            entitlement_ids: [standard, premium]
```

### 2. Run the sync command

```sh
dart run ann_flutter_flavor sync
```

This generates `lib/generated/ann_flavor.g.dart` with typed config classes for every flavor.

### 3. Call `setupFlavor` in each flavor entry point

```dart
// lib/flavors/main_my_app.dart
import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:my_app/generated/ann_flavor.g.dart';

void main() {
  setupFlavor(AnnFlavorKey.myApp, _detectPlatform());
  runApp(const MyApp());
}
```

### 4. Access flavor data anywhere

```dart
AnnFlavor.current.name        // "My App"
AnnFlavor.current.androidId   // "com.example.myapp"
AnnFlavor.platform            // AnnPlatform.android
AnnFlavor.current.subscriptions(AnnFlavor.platform)?.first.apiKey
```

---

## CLI Commands

| Command | Description |
|---------|-------------|
| `dart run ann_flutter_flavor sync` | Generate flavor code and wire Android/iOS |
| `dart run ann_flutter_flavor validate` | Validate `annspec.yaml` for missing required fields |

Both commands accept `-p <path>` to point at a Flutter project other than the current directory.

---

## Runtime API

| Symbol | Description |
|--------|-------------|
| `AnnFlavor.init(config:, platform:)` | Initialize (called by `setupFlavor`) |
| `AnnFlavor.current` | The active `AnnFlavorConfig` |
| `AnnFlavor.platform` | The active `AnnPlatform` |
| `AnnFlavor.key` | Shorthand for `AnnFlavor.current.key` |
| `AnnPlatform` | `android`, `ios`, `web`, `windows` |
| `AnnSubscription` | `apiKey` + `entitlementIds` |
| `AnnAuthConfig` | `clientId` + `reversedClientId` |

---

## License

MIT
