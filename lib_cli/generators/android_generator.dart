import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ann_flutter_flavor/src/plugin_versions.dart';
import '../model/annspec_model.dart';

const _pluginId = 'dev.anntech.flavorize';

// ── DSL resolver ──────────────────────────────────────────────────────────────

enum _GradleDsl { kts, groovy }

class _GradleFile {
  final File file;
  final _GradleDsl dsl;
  _GradleFile(this.file, this.dsl);
}

/// Returns the first Gradle file that exists: prefers .kts, falls back to .gradle.
/// [pathSegments] should be the path including the base filename (e.g. ['android', 'app', 'build.gradle']).
_GradleFile? _resolveGradle(List<String> pathSegments) {
  final base       = p.joinAll(pathSegments);
  final ktsFile    = File('$base.kts');
  final groovyFile = File(base);

  if (ktsFile.existsSync())    return _GradleFile(ktsFile,    _GradleDsl.kts);
  if (groovyFile.existsSync()) return _GradleFile(groovyFile, _GradleDsl.groovy);
  return null;
}

/// Ensures the ANN Gradle plugin is wired into the Android project.
/// Supports both Kotlin DSL (build.gradle.kts) and Groovy DSL (build.gradle).
class AndroidGenerator {
  static void generate(String projectRoot, [AnnspecModel? spec]) {
    final androidDir = Directory(p.join(projectRoot, 'android'));
    if (!androidDir.existsSync()) {
      print('  ⚠ No android/ directory found — skipping Android wiring.');
      return;
    }
    _patchSettings(androidDir, kGradlePluginVersion);
    _patchAppBuild(androidDir);

    if (spec != null) {
      final android = spec.platform('android');
      if (android != null) {
        _generateFlavorManifests(androidDir, android);
      }
    }
  }

  static void _patchSettings(Directory androidDir, String pluginVersion) {
    final gf = _resolveGradle([androidDir.path, 'settings.gradle']);
    if (gf == null) return;

    var content = gf.file.readAsStringSync();
    final label = p.basename(gf.file.path);
    var changed = false;

    // Ensure mavenCentral() is inside the pluginManagement repositories block.
    // Match the first `repositories {` in the file (always inside pluginManagement
    // in Flutter-generated settings files). We avoid [^}]* span issues by matching
    // only the repositories opening brace, not the entire pluginManagement block.
    // Ensure mavenCentral() is at the end of the pluginManagement repositories block.
    if (!_hasInPluginManagementRepositories(content, 'mavenCentral()')) {
      content = content.replaceFirstMapped(
        RegExp(r'(pluginManagement\b.*?repositories\s*\{[^}]*?)(\s*\})', dotAll: true),
        (m) => '${m.group(1)}\n        // Added by ann_flutter_flavor\n        mavenCentral()${m.group(2)}',
      );
      changed = true;
      print('  ✓ Added mavenCentral() to android/$label pluginManagement.repositories.');
    }

    // Ensure the ANN plugin declaration is at the end of the top-level plugins block.
    // Flutter projects place `plugins {}` as a top-level block outside pluginManagement.
    if (!content.contains(_pluginId)) {
      final idLine = gf.dsl == _GradleDsl.kts
          ? '    id("$_pluginId") version "$pluginVersion" apply false'
          : '    id \'$_pluginId\' version \'$pluginVersion\' apply false';
      final injection = '    // Added by ann_flutter_flavor\n$idLine';
      content = content.replaceFirstMapped(
        RegExp(r'^(plugins\s*\{[^}]*?)\s*(\n\})', multiLine: true),
        (m) => '${m.group(1)}\n$injection${m.group(2)}',
      );
      changed = true;
      print('  ✓ Added ANN Gradle plugin to android/$label.');
    } else {
      print('  ✓ Android $label already has ANN Gradle plugin.');
    }

    if (changed) gf.file.writeAsStringSync(content);
  }

  /// Returns true when [token] appears inside the pluginManagement repositories block.
  static bool _hasInPluginManagementRepositories(String content, String token) {
    // Capture everything inside pluginManagement { … } (up to the first `}` at column 0).
    final pmMatch = RegExp(
      r'pluginManagement\s*\{(.*?)^\}',
      dotAll: true,
      multiLine: true,
    ).firstMatch(content);
    if (pmMatch == null) return false;
    final pmBody = pmMatch.group(1)!;
    final repoMatch = RegExp(
      r'repositories\s*\{(.*?)\}',
      dotAll: true,
    ).firstMatch(pmBody);
    if (repoMatch == null) return false;
    return repoMatch.group(1)!.contains(token);
  }

  static void _patchAppBuild(Directory androidDir) {
    final gf = _resolveGradle([androidDir.path, 'app', 'build.gradle']);
    if (gf == null) return;

    var content = gf.file.readAsStringSync();
    final label = p.basename(gf.file.path);

    if (content.contains(_pluginId)) {
      print('  ✓ Android app/$label already applies ANN Gradle plugin.');
      return;
    }

    final idLine = gf.dsl == _GradleDsl.kts
        ? '    id("$_pluginId")'
        : '    id \'$_pluginId\'';
    final injection = '    // Added by ann_flutter_flavor\n$idLine';

    content = content.replaceFirstMapped(
      RegExp(r'(plugins\s*\{[^}]*?)\s*(\n\})'),
      (m) => '${m.group(1)}\n$injection${m.group(2)}',
    );

    gf.file.writeAsStringSync(content);
    print('  ✓ Patched android/app/$label with ANN Gradle plugin.');
  }

  // ── AndroidManifest.xml ────────────────────────────────────────────────────

  /// Ensures the launcher activity has the flutter default intent-filter.
  /// Currently a no-op placeholder — extend as needed per project.
  static void patchManifest(String projectRoot) {
    final file = File(
      p.join(projectRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!file.existsSync()) {
      print('  ⚠ AndroidManifest.xml not found — skipping.');
      return;
    }
    // Placeholder: add manifest patches here when needed.
    print('  ✓ AndroidManifest.xml — no patches required.');
  }

  /// Creates android/app/src/<flavor>/AndroidManifest.xml for each flavor if missing,
  /// and patches in GMS Ads meta-data when the flavor declares gms_ads_id.
  static void _generateFlavorManifests(Directory androidDir, AnnspecPlatform android) {
    for (final flavor in android.flavors) {
      final dir = Directory(p.join(androidDir.path, 'app', 'src', flavor.key));
      final manifestFile = File(p.join(dir.path, 'AndroidManifest.xml'));
      final hasAds = flavor.gmsAdsId != null;

      if (!manifestFile.existsSync()) {
        dir.createSync(recursive: true);
        manifestFile.writeAsStringSync(_flavorManifest(includeAds: hasAds));
        print('  ✓ Created android/app/src/${flavor.key}/AndroidManifest.xml'
            '${hasAds ? ' (with GMS Ads meta-data)' : ''}');
        continue;
      }

      // Manifest exists — patch GMS Ads meta-data if the flavor now has gms_ads_id.
      if (hasAds) {
        _patchAdsMetaData(manifestFile, flavor.key);
      }
    }
  }

  static void _patchAdsMetaData(File manifestFile, String flavorKey) {
    const gmsVersionTag =
        'android:name="com.google.android.gms.version"';
    const gmsAdsTag =
        'android:name="com.google.android.gms.ads.APPLICATION_ID"';

    var content = manifestFile.readAsStringSync();
    var changed = false;

    // Both entries go inside <application>. We insert before </application>.
    if (!content.contains(gmsVersionTag)) {
      content = content.replaceFirst(
        '</application>',
        '        <meta-data android:name="com.google.android.gms.version"'
            ' android:value="@integer/google_play_services_version"/>\n'
            '    </application>',
      );
      changed = true;
    }
    if (!content.contains(gmsAdsTag)) {
      content = content.replaceFirst(
        '</application>',
        '        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"'
            ' android:value="@string/gms_ads_id"/>\n'
            '    </application>',
      );
      changed = true;
    }

    if (changed) {
      manifestFile.writeAsStringSync(content);
      print('  ✓ Patched android/app/src/$flavorKey/AndroidManifest.xml with GMS Ads meta-data.');
    } else {
      print('  ✓ android/app/src/$flavorKey/AndroidManifest.xml already has GMS Ads meta-data.');
    }
  }

  static String _flavorManifest({bool includeAds = false}) {
    final adsMeta = includeAds ? '''
        <meta-data android:name="com.google.android.gms.version"
            android:value="@integer/google_play_services_version"/>
        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="@string/gms_ads_id"/>''' : '';
    return '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by ann_flutter_flavor — do not delete. -->
<!-- Overrides android:label to use the per-flavor app_name string resource
     set by the ANN Gradle plugin via resValue. -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="@string/app_name">${adsMeta.isEmpty ? '' : '\n$adsMeta'}
    </application>
</manifest>
''';
  }
}
