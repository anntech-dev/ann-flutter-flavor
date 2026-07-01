import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

const _podPluginName = 'ann-ios-flavorize';

/// Handles iOS wiring: CocoaPods plugin, per-flavor xcconfig files, Info.plist patches.
class IosGenerator {
  static void generate(String projectRoot, AnnspecModel spec) {
    final iosDir = Directory(p.join(projectRoot, 'ios'));
    if (!iosDir.existsSync()) {
      print('  ⚠ No ios/ directory found — skipping iOS wiring.');
      return;
    }

    _patchPodfile(iosDir);

    final iosPlatform = spec.platform('ios');
    if (iosPlatform == null || iosPlatform.flavors.isEmpty) {
      print('  ✓ No iOS flavors defined — skipping xcconfig/Info.plist generation.');
      return;
    }

    _generateXcconfigs(iosDir, iosPlatform);
    _patchInfoPlist(iosDir, iosPlatform);
  }

  // ── CocoaPods ──────────────────────────────────────────────────────────────

  static void _patchPodfile(Directory iosDir) {
    final file = File(p.join(iosDir.path, 'Podfile'));
    if (!file.existsSync()) {
      print('  ⚠ ios/Podfile not found — skipping iOS wiring.');
      return;
    }

    var content = file.readAsStringSync();
    if (content.contains(_podPluginName)) {
      print('  ✓ ios/Podfile already has ANN CocoaPods plugin.');
      return;
    }

    content = "# Added by ann_flutter_flavor — multi-flavor iOS build configuration\nplugin '$_podPluginName'\n" + content;
    file.writeAsStringSync(content);
    print('  ✓ Patched ios/Podfile with ANN CocoaPods plugin.');
  }

  // ── xcconfig generation ────────────────────────────────────────────────────

  static void _generateXcconfigs(Directory iosDir, AnnspecPlatform platform) {
    final flutterDir = Directory(p.join(iosDir.path, 'Flutter'));
    if (!flutterDir.existsSync()) {
      print('  ⚠ ios/Flutter/ not found — skipping xcconfig generation.');
      return;
    }

    for (final flavor in platform.flavors) {
      // Determine which build types to generate — always at least debug + release.
      final buildTypeKeys = <String>{
        'debug',
        'release',
        ...flavor.buildTypes.keys,
        ...platform.defaultBuildTypes.keys,
      };

      for (final bt in buildTypeKeys) {
        _generateXcconfig(flutterDir, platform, flavor, bt);
      }
    }
  }

  static void _generateXcconfig(
    Directory flutterDir,
    AnnspecPlatform platform,
    AnnspecFlavor flavor,
    String buildType,
  ) {
    final fileName = '${flavor.key}${_capitalize(buildType)}.xcconfig';
    final file = File(p.join(flutterDir.path, fileName));

    // Compute effective values (flavor overrides default).
    final effectiveBundleId = (platform.baseId ?? '') +
        (flavor.idSuffix ?? '') +
        (flavor.buildTypes[buildType]?.idSuffix ?? '');
    final effectiveName    = flavor.name ?? platform.baseName ?? '';
    final effectiveVersion = flavor.versionName ?? platform.defaultVersionName ?? '';
    final effectiveBuild   = flavor.versionCode ?? platform.defaultVersionCode ?? '';
    final effectiveGmsAdsId = flavor.gmsAdsId ?? platform.defaultGmsAdsId;

    // Variables this xcconfig should declare.
    final vars = <String, String>{
      'PRODUCT_BUNDLE_IDENTIFIER': effectiveBundleId,
      'APP_NAME': effectiveName,
      'FLUTTER_BUILD_NAME': effectiveVersion,
      'FLUTTER_BUILD_NUMBER': effectiveBuild,
      if (effectiveGmsAdsId != null)
        'GAD_APPLICATION_IDENTIFIER': effectiveGmsAdsId,
    };

    if (!file.existsSync()) {
      // Create fresh.
      final isDebug = buildType.toLowerCase() == 'debug';
      final baseInclude = isDebug ? 'Debug' : 'Release';
      final lines = [
        '// Added by ann_flutter_flavor',
        '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.${buildType.toLowerCase()}-${flavor.key}.xcconfig"',
        '#include "$baseInclude.xcconfig"',
        '#include "Generated.xcconfig"',
        '',
        ...vars.entries.map((e) => '${e.key}=${e.value}'),
      ];
      file.writeAsStringSync(lines.join('\n') + '\n');
      print('  ✓ Created ios/Flutter/$fileName');
    } else {
      // Patch: add missing variables only.
      var content = file.readAsStringSync();
      var patched = false;
      final additions = <String>[];

      for (final entry in vars.entries) {
        // Match "KEY=" at start of line (value may differ — we only add if key absent).
        final keyPattern = RegExp('^${RegExp.escape(entry.key)}=', multiLine: true);
        if (!keyPattern.hasMatch(content)) {
          additions.add('${entry.key}=${entry.value}');
          patched = true;
        }
      }

      if (patched) {
        content = content.trimRight() +
            '\n// Added by ann_flutter_flavor\n' +
            additions.join('\n') +
            '\n';
        file.writeAsStringSync(content);
        print('  ✓ Patched ios/Flutter/$fileName (added: ${additions.map((l) => l.split('=').first).join(', ')})');
      } else {
        print('  ✓ ios/Flutter/$fileName already up-to-date.');
      }
    }
  }

  // ── Info.plist patching ────────────────────────────────────────────────────

  static void _patchInfoPlist(Directory iosDir, AnnspecPlatform platform) {
    final plistFile = File(p.join(iosDir.path, 'Runner', 'Info.plist'));
    if (!plistFile.existsSync()) {
      print('  ⚠ ios/Runner/Info.plist not found — skipping.');
      return;
    }

    var content = plistFile.readAsStringSync();
    var patched = false;

    // Keys that should use xcconfig variable references.
    final requiredEntries = <String, String>{
      'CFBundleIdentifier': r'$(PRODUCT_BUNDLE_IDENTIFIER)',
      'CFBundleDisplayName': r'$(APP_NAME)',
      'CFBundleShortVersionString': r'$(FLUTTER_BUILD_NAME)',
      'CFBundleVersion': r'$(FLUTTER_BUILD_NUMBER)',
    };

    // AdMob key — only inject if any flavor (or default) has gms_ads_id.
    final hasAdmob = platform.defaultGmsAdsId != null ||
        platform.flavors.any((f) => f.gmsAdsId != null);
    if (hasAdmob) {
      requiredEntries['GADApplicationIdentifier'] = r'$(GAD_APPLICATION_IDENTIFIER)';
    }

    for (final entry in requiredEntries.entries) {
      final keyTag = '<key>${entry.key}</key>';
      final valueTag = '<string>${entry.value}</string>';

      if (!content.contains(keyTag)) {
        // Key entirely absent — inject before </dict> closing the root dict.
        content = content.replaceFirst(
          '</dict>\n</plist>',
          '\t$keyTag\n\t$valueTag\n</dict>\n</plist>',
        );
        patched = true;
        print('  ✓ Info.plist: added ${entry.key}');
      } else {
        // Key present — check if value is already a variable reference.
        final currentValuePattern = RegExp(
          '${RegExp.escape(keyTag)}\\s*<string>(.*?)</string>',
          dotAll: true,
        );
        final match = currentValuePattern.firstMatch(content);
        if (match != null && match.group(1) != entry.value) {
          // Replace only if it's a hardcoded value, not already a variable.
          final existing = match.group(1)!;
          if (!existing.startsWith(r'$(')) {
            content = content.replaceFirst(
              '${match.group(0)}',
              '$keyTag\n\t${valueTag}',
            );
            patched = true;
            print('  ✓ Info.plist: updated ${entry.key} to variable reference');
          }
        }
      }
    }

    if (patched) {
      plistFile.writeAsStringSync(content);
    } else {
      print('  ✓ ios/Runner/Info.plist already up-to-date.');
    }
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
