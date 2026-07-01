import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../spec/annspec_reader.dart';
import '../model/annspec_model.dart';

const _androidOnlyBuildTypeFields = [
  'minifyEnabled', 'shrinkResources', 'lintCheckReleaseBuilds',
  'ndkVersion', 'ndkDebugSymbolLevel', 'ndkAbiFilters',
];

class _Issue {
  final String path;
  final String message;
  final String? fix;
  const _Issue(this.path, this.message, {this.fix});
}

class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';

  @override
  final description = 'Validate annspec.yaml structure and report any issues.';

  ValidateCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
    argParser.addOption(
      'format',
      allowed: ['human', 'json'],
      defaultsTo: 'human',
      help: 'Output format: "human" (default) or "json" for machine consumers.',
    );
  }

  @override
  Future<void> run() async {
    final jsonMode = (argResults!['format'] as String) == 'json';
    // Wrap everything so stdout is always valid JSON in json mode.
    try {
      await _runValidate(jsonMode);
    } catch (e) {
      if (jsonMode) {
        _printJson('annspec.yaml', [], [], parseError: 'Internal error: $e');
      } else {
        rethrow;
      }
      exitCode = 1;
    }
  }

  Future<void> _runValidate(bool jsonMode) async {
    final projectRoot = argResults!['project'] as String;
    final specPath = p.join(projectRoot, 'annspec.yaml');

    if (!jsonMode) {
      print('ANN Flavor — validating annspec.yaml in $projectRoot');
      print('');
    }

    final errors   = <_Issue>[];
    final warnings = <_Issue>[];

    AnnspecModel spec;
    YamlMap rawDoc;

    try {
      spec   = AnnspecReader.read(projectRoot);
      rawDoc = loadYaml(File(specPath).readAsStringSync()) as YamlMap;
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      if (jsonMode) {
        _printJson(specPath, [], [], parseError: msg);
        exitCode = 1;
      } else {
        print('  ✗  Cannot read annspec.yaml:\n     $msg');
      }
      return;
    }

    // Warn if enabled: false — validation still runs on the whole file.
    final specEnabled = rawDoc['enabled'] as bool? ?? true;
    if (!specEnabled) {
      warnings.add(_Issue(
        'enabled',
        'annspec.yaml is disabled (enabled: false) — '
            'all plugins will skip this file and apply no configuration.',
        fix: 'Set  enabled: true  to re-activate, '
            'or remove the field (defaults to true).',
      ));
    }

    final rawApp = rawDoc['app'] as YamlMap?;

    for (final platform in spec.platforms) {
      _validatePlatform(platform, rawApp, errors, warnings);
    }

    _checkFirebaseIntegration(spec, errors, warnings);
    _checkDeprecatedFirebaseFields(rawDoc, errors);

    if (jsonMode) {
      _printJson(specPath, errors, warnings);
    } else {
      _printResults(errors, warnings);
    }
    if (errors.isNotEmpty) exitCode = 1;
  }

  // ── Platform ───────────────────────────────────────────────────────────────

  void _validatePlatform(
    AnnspecPlatform platform,
    YamlMap? rawApp,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    final plat       = platform.key;
    final rawPlatform = rawApp?[plat] as YamlMap?;
    final basePath   = 'app.$plat';

    if (platform.baseId == null) {
      errors.add(_Issue(
        '$basePath.default',
        '"id" is required but not set.',
        fix: 'Add:  id: "com.example.myapp"  under  $basePath.default',
      ));
    }

    if (platform.flavors.isEmpty) {
      errors.add(_Issue(
        '$basePath.flavor',
        'No flavors defined — at least one flavor is required.',
        fix: 'Add a flavor block under  $basePath.flavor',
      ));
    }

    // Signing credential warnings
    final hasRelease = platform.defaultFirebaseRelease != null ||
        platform.flavors.any((f) => f.firebaseRelease != null);
    if (hasRelease) {
      if (plat == 'android' && platform.signingKeyFile == null) {
        warnings.add(_Issue(
          '$basePath.default.credentials.signing',
          '"key_file" is not set — release builds may fail to sign.',
          fix: 'Add:  signing:\n          key_file: "keys/keystore.properties"',
        ));
      }
      if (plat == 'ios' && platform.teamId == null) {
        warnings.add(_Issue(
          '$basePath.default.credentials.signing',
          '"team_id" is not set — release builds may fail to sign.',
          fix: 'Add:  signing:\n          team_id: "YOURTEAMID"',
        ));
      }
    }

    // Default build_type checks
    _checkFirebase('$basePath.default.build_types.release.firebase',
        platform.defaultFirebaseRelease, plat, errors, warnings,
        resolvedServiceAccount: AnnspecModel.resolveServiceAccount(platform, null, 'release'));
    _checkFirebase('$basePath.default.build_types.debug.firebase',
        platform.defaultFirebaseDebug,   plat, errors, warnings,
        resolvedServiceAccount: AnnspecModel.resolveServiceAccount(platform, null, 'debug'));

    final rawDefault = rawPlatform?['default'] as YamlMap?;
    _checkBuildTypeFields('$basePath.default',
        plat, rawDefault?['build_types'] as YamlMap?, errors);

    for (final flavor in platform.flavors) {
      _validateFlavor(flavor, platform, rawPlatform, errors, warnings);
    }
  }

  // ── Flavor ─────────────────────────────────────────────────────────────────

  void _validateFlavor(
    AnnspecFlavor flavor,
    AnnspecPlatform platform,
    YamlMap? rawPlatform,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    final plat     = platform.key;
    final flv      = flavor.key;
    final basePath = 'app.$plat.flavor.$flv';
    final rawFlavor = (rawPlatform?['flavor'] as YamlMap?)?[flv] as YamlMap?;

    // Required fields
    if (flavor.name == null) {
      errors.add(_Issue(
        '$basePath.name',
        '"name" is required but not set.',
        fix: 'Add:  name: "My App ${_titleCase(flv)}"',
      ));
    }
    if (flavor.mainFile == null) {
      errors.add(_Issue(
        '$basePath.main_file',
        '"main_file" is required but not set.',
        fix: 'Add:  main_file: "lib/flavors/main_$flv.dart"',
      ));
    }
    if (flavor.versionName == null) {
      errors.add(_Issue(
        '$basePath.version_name',
        '"version_name" is required but not set.',
        fix: 'Add:  version_name: "1.0.0"',
      ));
    }
    if (flavor.versionCode == null) {
      errors.add(_Issue(
        '$basePath.version_code',
        '"version_code" is required but not set.',
        fix: 'Add:  version_code: 100000',
      ));
    }

    // id vs id_suffix mutual exclusion
    if (flavor.id != null && flavor.idSuffix != null) {
      errors.add(_Issue(
        '$basePath',
        'Both "id" and "id_suffix" are set — use one, not both.',
        fix: 'Use "id" to override the full bundle ID, '
            'or "id_suffix" to append to default.id.  Remove one.',
      ));
    }
    if (flavor.id == null && flavor.idSuffix == null) {
      warnings.add(_Issue(
        '$basePath',
        'Neither "id" nor "id_suffix" is set — this flavor will share the same bundle ID as default.',
        fix: 'Add:  id_suffix: ".$flv"  to make the ID unique, '
            'or  id: "com.example.$flv"  for a full override.',
      ));
    }

    // Firebase checks
    _checkFirebase('$basePath.build_types.release.firebase',
        flavor.firebaseRelease, plat, errors, warnings,
        resolvedServiceAccount: AnnspecModel.resolveServiceAccount(platform, flavor, 'release'));
    _checkFirebase('$basePath.build_types.debug.firebase',
        flavor.firebaseDebug,   plat, errors, warnings,
        resolvedServiceAccount: AnnspecModel.resolveServiceAccount(platform, flavor, 'debug'));

    // Wrong-platform store fields
    if (plat == 'ios') {
      if (flavor.googlePlayPriority != null)
        errors.add(_Issue(
          '$basePath.stores.google_play',
          '"google_play" is Android-only — not valid under iOS.',
          fix: 'Remove the google_play block from  $basePath.stores',
        ));
      if (flavor.samsungAppId != null)
        errors.add(_Issue(
          '$basePath.stores.samsung_galaxy',
          '"samsung_galaxy" is Android-only — not valid under iOS.',
          fix: 'Remove the samsung_galaxy block from  $basePath.stores',
        ));
      if (flavor.amazonAppId != null)
        errors.add(_Issue(
          '$basePath.stores.amazon',
          '"amazon" is Android-only — not valid under iOS.',
          fix: 'Remove the amazon block from  $basePath.stores',
        ));
    }
    if (plat == 'android') {
      if (flavor.appleId != null)
        errors.add(_Issue(
          '$basePath.stores.app_store',
          '"app_store" is iOS-only — not valid under Android.',
          fix: 'Remove the app_store block from  $basePath.stores',
        ));
    }

    // google_play.priority range
    if (flavor.googlePlayPriority != null) {
      final priority = int.tryParse(flavor.googlePlayPriority!);
      if (priority == null || priority < 1 || priority > 5) {
        errors.add(_Issue(
          '$basePath.stores.google_play.priority',
          '"priority" must be an integer from 1 to 5 '
              '(got: ${flavor.googlePlayPriority}).',
          fix: '1 = background update (lowest urgency), '
              '5 = immediate/forced update (highest urgency).',
        ));
      }
    }

    // Android-only build_type fields on other platforms
    _checkBuildTypeFields(basePath, plat,
        rawFlavor?['build_types'] as YamlMap?, errors);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _checkFirebase(
    String path,
    AnnspecFirebase? firebase,
    String platformKey,
    List<_Issue> errors,
    List<_Issue> warnings, {
    required String? resolvedServiceAccount,
  }) {
    if (firebase == null) return;

    if (firebase.configFile != null && firebase.projectId != null) {
      errors.add(_Issue(
        path,
        '"config_file" and "project_id" are both set — use one, not both.',
        fix: 'Use "config_file" (path to google-services.json) on Android, '
            'or "project_id" (Firebase project ID) for flutterfire configure.',
      ));
    }
    if (platformKey == 'ios' && firebase.configFile != null) {
      errors.add(_Issue(
        path,
        '"config_file" is Android-only — iOS downloads its config via "project_id" at build time.',
        fix: 'Replace  config_file: "..."  with  project_id: "your-firebase-project-id"',
      ));
    }
    // project_id mode requires a service_account resolved via the 4-level cascade;
    // without it flutterfire configure will fail (REQ-FIRE-00100).
    if (firebase.projectId != null && resolvedServiceAccount == null) {
      warnings.add(_Issue(
        path,
        '"project_id" is set but no "service_account" resolves for this build — '
            'flutterfire configure will fail without credentials.',
        fix: 'Add:  service_account: "keys/firebase-sa.json"  '
            'at default.firebase, default.build_types.<bt>.firebase, '
            'flavor.firebase, or flavor.build_types.<bt>.firebase level.',
      ));
    }
    // service_account with config_file mode is ineffective — service_account is only used
    // by flutterfire configure, which only runs in project_id mode.
    if (firebase.serviceAccount != null && firebase.configFile != null && firebase.projectId == null) {
      warnings.add(_Issue(
        path,
        '"service_account" is set but the mode is "config_file" — '
            'service_account is only used with project_id mode.',
        fix: 'Remove "service_account" or switch to "project_id" mode.',
      ));
    }
  }

  // ── Firebase integration gate ──────────────────────────────────────────────

  void _checkFirebaseIntegration(
    AnnspecModel spec,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    if (spec.integrations?.firebase != true) return;

    // integrations.firebase: true but no firebase blocks found anywhere is likely a mistake.
    final hasAny = spec.platforms.any((p) =>
        p.defaultFirebaseRelease != null ||
        p.defaultFirebaseDebug != null ||
        p.flavors.any((f) => f.firebaseRelease != null || f.firebaseDebug != null));

    if (!hasAny) {
      warnings.add(_Issue(
        'integrations.firebase',
        'integrations.firebase is true but no firebase blocks are configured on any platform.',
        fix: 'Add firebase blocks under build_types, or set integrations.firebase: false.',
      ));
    }
  }

  // ── Deprecated field scanner ───────────────────────────────────────────────

  // Scan the raw YAML for deprecated fields. No backward compatibility (REQ-FIRE-00180) —
  // these are errors, not warnings, and no automatic migration is performed.
  void _checkDeprecatedFirebaseFields(YamlMap rawDoc, List<_Issue> errors) {
    // Top-level app.general.firebase_token_file
    final general = (rawDoc['app'] as YamlMap?)?['general'] as YamlMap?;
    if (general != null && general.containsKey('firebase_token_file')) {
      errors.add(_Issue(
        'app.general.firebase_token_file',
        '"firebase_token_file" was removed in v0.3.0 — machine auth is no longer supported.',
        fix: 'Add  service_account: "keys/firebase-sa.json"  inside each build_type.firebase block. '
            'See the Firebase Setup guide for service account creation steps.',
      ));
    }
    _scanForDeprecatedFirebase(rawDoc, '', errors);
  }

  static const _knownFirebaseKeys = {
    'config_file', 'project_id', 'service_account',
    // 'file' is intentionally absent — caught separately as a deprecated-field error.
  };

  void _scanForDeprecatedFirebase(dynamic node, String path, List<_Issue> errors) {
    if (node is! YamlMap) return;
    for (final entry in node.entries) {
      final key = entry.key as String;
      final childPath = path.isEmpty ? key : '$path.$key';
      if (key == 'firebase' && entry.value is YamlMap) {
        final fb = entry.value as YamlMap;
        if (fb.containsKey('file')) {
          errors.add(_Issue(
            '$childPath.file',
            '"firebase.file" was renamed to "firebase.config_file" in v0.3.0.',
            fix: 'Rename  file: "..."  to  config_file: "..."  in this firebase block.',
          ));
        }
        for (final fbKey in fb.keys.cast<String>()) {
          if (!_knownFirebaseKeys.contains(fbKey) && fbKey != 'file') {
            errors.add(_Issue(
              '$childPath.$fbKey',
              '"$fbKey" is not a recognised firebase field.',
              fix: 'Valid fields are: config_file, project_id, service_account.',
            ));
          }
        }
      }
      _scanForDeprecatedFirebase(entry.value, childPath, errors);
    }
  }

  void _checkBuildTypeFields(
    String contextPath,
    String platformKey,
    YamlMap? buildTypesRaw,
    List<_Issue> errors,
  ) {
    if (buildTypesRaw == null || platformKey != 'ios') return;

    for (final btEntry in buildTypesRaw.entries) {
      final btKey = btEntry.key as String;
      final btMap = btEntry.value as YamlMap?;
      if (btMap == null) continue;

      for (final field in _androidOnlyBuildTypeFields) {
        if (btMap.containsKey(field)) {
          errors.add(_Issue(
            '$contextPath.build_types.$btKey.$field',
            '"$field" is Android-only — not valid inside an iOS build_type.',
            fix: 'Remove "$field" from  $contextPath.build_types.$btKey',
          ));
        }
      }
    }
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Output ─────────────────────────────────────────────────────────────────

  void _printJson(
    String specPath,
    List<_Issue> errors,
    List<_Issue> warnings, {
    String? parseError,
  }) {
    final errList = parseError != null
        ? [
            {'severity': 'error', 'path': 'annspec.yaml', 'message': parseError, 'fix': null}
          ]
        : errors
            .map((e) => {'severity': 'error', 'path': e.path, 'message': e.message, 'fix': e.fix})
            .toList();

    final warnList = warnings
        .map((w) => {'severity': 'warning', 'path': w.path, 'message': w.message, 'fix': w.fix})
        .toList();

    print(jsonEncode({
      'valid': errList.isEmpty,
      'specPath': p.absolute(specPath),
      'errors': errList,
      'warnings': warnList,
    }));
  }

  void _printResults(List<_Issue> errors, List<_Issue> warnings) {
    if (warnings.isNotEmpty) {
      print('  ⚠  ${warnings.length} warning${warnings.length == 1 ? '' : 's'}:');
      for (final w in warnings) _printIssue(w, isError: false);
      print('');
    }

    if (errors.isEmpty) {
      print('  ✅  annspec.yaml is valid${warnings.isEmpty ? '.' : ' (with warnings above).'}');
    } else {
      print('  ✗  ${errors.length} error${errors.length == 1 ? '' : 's'}:');
      for (final e in errors) _printIssue(e, isError: true);
    }
  }

  void _printIssue(_Issue issue, {required bool isError}) {
    final icon = isError ? '✗' : '⚠';
    print('');
    print('    $icon  ${issue.path}');
    print('       ${issue.message}');
    if (issue.fix != null) {
      print('       → ${issue.fix}');
    }
  }
}
