# Changelog

## 0.4.0 (unreleased)

**`--firebase-mode script`** — `sync` accepts `--firebase-mode script` to write
`lib/generated/scripts/firebase.sh` instead of running `flutterfire configure` inline.
Use when Firebase auth is unavailable at sync time (e.g. the service account is decoded
in a later CI step). The generated script navigates to the project root automatically.

**iOS `config_file` guard** — sync now aborts with a clear error when an iOS firebase
block has `config_file` without `project_id`. iOS must use `project_id` mode; config_file
is Android-only.

---

## 0.4.0

**`sync` pre-flight validation** — `sync` now runs `validate` before generating any
files. If the spec has errors, sync aborts immediately with exit 1 and no files are
written. Warnings are printed but generation continues.

**Step reorder** — Firebase (`flutterfire configure`) now runs after the fast
deterministic steps (Dart → Android → iOS) instead of second. New step order:
`[0]` validate → `[1]` Dart → `[2]` Android → `[3]` iOS → `[4]` Firebase →
`[5]` Fastlane → `[6]` Melos.

**`--format json`** — `sync` and `validate` accept `--format json` to emit the
pre-flight result as machine-readable JSON on stdout. All other output goes to stderr.
Useful for IDE integrations and CI pipelines.

**`doctor` command** — replaces `version`. Shows the `ann_flutter_flavor` version and
checks each linked plugin's installed version against the expected target. The old
`version` command has been removed.

**Firebase: `config_file` on iOS is now a hard error** — `sync` exits 1 immediately
when an iOS firebase block contains `config_file`. iOS must use `project_id` (which
triggers `flutterfire configure` to generate the options file). See the Firebase Setup
section in the README for setup guidance.

## 0.3.0

**Firebase service account auth** — `flutterfire configure` now authenticates
exclusively via the `service_account` field in `annspec.yaml`. ADC (`gcloud auth`) and
`firebase login` are no longer used or supported. Set `service_account` in your firebase
block alongside `project_id`; `sync` will warn if `project_id` is set without a
service account.

**`validate --format json`** — the `validate` command now accepts `--format json`,
emitting a single JSON object on stdout with all errors and warnings. Exit code 1 when
any error is present. Used by the Studio plugin (1.1.0) for IDE-integrated validation.

**`version` command** — new command that reads `pubspec.lock`,
`android/settings.gradle.kts`, and `Gemfile.lock` to compare installed plugin versions
against expected targets. Exits 1 when any detectable plugin is outdated.

**Firebase validation improvements** — new checks:
- Error: `firebase.file` key (renamed to `config_file` in 0.1.6) is now a hard error with a migration hint
- Warning: `project_id` set without a `service_account`
- Warning: `service_account` set alongside `config_file` (ineffective)
- Warning: `integrations.firebase: true` set but no firebase blocks configured in spec

## 0.2.5

Internal publish-workflow improvements. No user-facing changes.

## 0.2.4

**120-second timeout on `flutterfire configure`** — prevents sync from hanging
indefinitely when auth prompts or network issues stall the FlutterFire CLI.

**Signing path resolution** — relative cert/key paths in `credentials.signing` are
now resolved to absolute paths before being passed to Gradle, preventing build failures
when `pod install` or `gradle` are invoked from a different working directory.

## 0.2.2

**Redesigned `summary` command** — output is now organised by flavor × build type,
showing fully resolved (cascaded) values for every field:

- Each flavor has a block per build type (`release`, `debug`, …)
- Every field shown is the effective value after the default → flavor → build type cascade: id, name, version, firebase, auth, admob, stores, custom, and Android build-type flags
- When no flavors are defined, the default values are shown per build type
- The old top-level "default" block is removed

## 0.2.1

**`enabled: false` support in validate** — if `annspec.yaml` sets `enabled: false`, the `validate` command now shows a warning at the top explaining that all plugins will ignore the file, while still running full structural validation on the rest of the spec.

**Improved `validate` output** — every error and warning now shows:
- The exact YAML path where the problem is (e.g. `app.android.flavor.free.stores.google_play.priority`)
- A precise description of what is wrong
- A `→` fix hint telling you what to add, change, or remove

Also: parse-time errors (missing `app:` root key, old `annai_app:` key) now print a clear message with a migration hint instead of a raw Dart type error.

## 0.2.0

**Breaking: `annai_app:` root key renamed to `app:`** — `annspec.yaml` files using the old
`annai_app:` root key must be updated. The CLI shows a clear migration hint if the old key
is detected.

## 0.1.9

Internal pub.dev score improvements (documentation, example, analysis options). No
user-facing behaviour changes.

## 0.1.7

**Expanded `validate` command** — comprehensive field-level checks across the entire spec:
bundle IDs, version formats, firebase mode conflicts, store IDs, signing paths, and
unknown field detection.

## 0.1.6

**`buildType` auto-detection** — `AnnFlavor.buildType` is now derived automatically
from Dart's `kDebugMode` / `kReleaseMode`. The `buildType` parameter is no longer
needed in `AnnFlavor.init()`.

**`flutterfire configure` invoked directly during sync** — removes the generated
`firebase.sh` shell script. Firebase configuration is now driven entirely by the
`project_id` field in `annspec.yaml`.

**Firebase config refactored** — `path`, `firebase_app_id`, and `build_target` fields
are replaced by two mutually exclusive modes:
- `config_file` — path to a static `google-services.json` / `GoogleService-Info.plist`
- `project_id` — runs `flutterfire configure` during sync to generate options files

**Example app added** — a real `flutter create` example with `free` / `pro` flavors
is included in the package.

## 0.1.4

**`integrations` block** — new top-level `integrations:` key in `annspec.yaml` with
`fastlane` and `melos` flags. When enabled:
- `fastlane: true` — `sync` generates a `Gemfile` wiring the Fastlane plugin
- `melos: true` — `sync` patches a managed block in `pubspec.yaml` with Melos scripts

The managed block uses start/end markers so user-authored content outside the block
is never overwritten.

## 0.1.3

Internal publish pipeline improvements (per-plugin tagging, unified workflow). No
user-facing behaviour changes.

## 0.1.2

Internal CI/workflow fix. No user-facing behaviour changes.

## 0.1.1

Initial release.
