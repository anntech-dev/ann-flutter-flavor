import 'dart:io';
import 'dart:convert';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../spec/annspec_reader.dart';
import '../generators/dart_generator.dart';
import '../generators/android_generator.dart';
import '../generators/ios_generator.dart';
import '../generators/firebase_generator.dart';
import '../generators/fastlane_generator.dart';
import '../generators/melos_generator.dart';

class SyncCommand extends Command<void> {
  @override
  final name = 'sync';

  @override
  final description =
      'Read annspec.yaml and sync all platform files (Dart codegen, '
      'Firebase options, Android Gradle wiring, iOS CocoaPods wiring).';

  SyncCommand() {
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Flutter project root.',
      defaultsTo: '.',
    );
    argParser.addFlag(
      'silent',
      abbr: 's',
      help: 'Skip interactive reauth prompts (used by IDE plugins).',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addOption(
      'format',
      allowed: ['human', 'json'],
      defaultsTo: 'human',
      help: 'Output format for pre-flight validation result.',
    );
    argParser.addOption(
      'firebase-mode',
      allowed: ['run', 'script'],
      defaultsTo: 'run',
      help: 'How to handle flutterfire configure during sync.\n'
          '"run" executes it inline (default).\n'
          '"script" writes lib/generated/scripts/firebase.sh instead.',
    );
  }

  @override
  Future<void> run() async {
    final projectRoot   = argResults!['project'] as String;
    final jsonMode      = (argResults!['format'] as String) == 'json';
    final firebaseMode  = argResults!['firebase-mode'] as String;

    if (!jsonMode) print('ANN Flavor — syncing $projectRoot\n');

    // Step 0 — pre-flight validation
    if (!jsonMode) print('[0/6] Validating annspec.yaml...');
    final valid = await _runValidation(projectRoot, jsonMode);
    if (!valid) return;

    if (!jsonMode) print('  ✓ Validation passed.\n');

    final spec = AnnspecReader.read(projectRoot);

    // Step 1 — Dart codegen (fast, deterministic)
    if (!jsonMode) print('[1/6] Generating Dart flavor file...');
    DartGenerator.generate(spec, projectRoot);

    // Step 2 — Android wiring (fast, deterministic)
    if (!jsonMode) print('\n[2/6] Wiring Android (Gradle plugin + defaultConfig)...');
    AndroidGenerator.generate(projectRoot, spec);

    // Step 3 — iOS wiring (fast, deterministic)
    if (!jsonMode) print('\n[3/6] Wiring iOS (CocoaPods plugin + xcconfig + Info.plist)...');
    IosGenerator.generate(projectRoot, spec);

    // Step 4 — Firebase
    if (!jsonMode) {
      final label = firebaseMode == 'script'
          ? '[4/6] Generating firebase.sh script...'
          : '[4/6] Running flutterfire configure (project_id flavors)...';
      print('\n$label');
    }
    try {
      await FirebaseGenerator.generate(spec, projectRoot, firebaseMode: firebaseMode);
    } on StateError catch (e) {
      stderr.writeln('  ✗ Firebase configuration error:\n  ${e.message}');
      exitCode = 1;
      return;
    }

    // Step 5 — Fastlane
    if (spec.integrations?.fastlane == true) {
      if (!jsonMode) print('\n[5/6] Setting up Fastlane (Gemfile)...');
      FastlaneGenerator.generate(projectRoot);
    } else {
      if (!jsonMode) print('\n[5/6] Fastlane integration disabled — skipping.');
    }

    // Step 6 — Melos
    if (spec.integrations?.melos == true) {
      if (!jsonMode) print('\n[6/6] Setting up Melos scripts (pubspec.yaml)...');
      MelosGenerator.generate(projectRoot, spec);
    } else {
      if (!jsonMode) print('\n[6/6] Melos integration disabled — skipping.');
    }

    if (!jsonMode) {
      print('\n✅  Sync complete.');
      print('    iOS: run `pod install` if Podfile changed.');
    }
  }

  // ── Pre-flight validation ───────────────────────────────────────────────────

  Future<bool> _runValidation(String projectRoot, bool jsonMode) async {
    final specPath = p.join(projectRoot, 'annspec.yaml');

    final errors   = <_Issue>[];
    final warnings = <_Issue>[];

    try {
      AnnspecReader.read(projectRoot);
      final rawDoc = loadYaml(File(specPath).readAsStringSync()) as YamlMap;
      _checkDeprecatedFirebaseFields(rawDoc, errors);
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      if (jsonMode) {
        _printValidationJson(specPath, [], [], parseError: msg);
      } else {
        stderr.writeln('  ✗  Cannot read annspec.yaml:\n     $msg');
        stderr.writeln('\n✗  annspec.yaml has errors — fix them before running sync.');
      }
      exitCode = 1;
      return false;
    }

    if (jsonMode) {
      if (errors.isNotEmpty) {
        _printValidationJson(specPath, errors, warnings);
        exitCode = 1;
        return false;
      }
    } else {
      if (warnings.isNotEmpty) {
        for (final w in warnings) {
          print('  ⚠  ${w.path}: ${w.message}');
        }
      }
      if (errors.isNotEmpty) {
        for (final e in errors) {
          stderr.writeln('  ✗  ${e.path}: ${e.message}');
        }
        stderr.writeln('\n✗  annspec.yaml has errors — fix them before running sync.');
        exitCode = 1;
        return false;
      }
    }

    return true;
  }

  void _checkDeprecatedFirebaseFields(YamlMap rawDoc, List<_Issue> errors) {
    _scanForDeprecatedFirebase(rawDoc, '', errors);
  }

  static const _knownFirebaseKeys = {'config_file', 'project_id', 'service_account'};

  void _scanForDeprecatedFirebase(dynamic node, String path, List<_Issue> errors) {
    if (node is! YamlMap) return;
    for (final entry in node.entries) {
      final key = entry.key as String;
      final childPath = path.isEmpty ? key : '$path.$key';
      if (key == 'firebase' && entry.value is YamlMap) {
        final fb = entry.value as YamlMap;
        for (final fbKey in fb.keys.cast<String>()) {
          if (!_knownFirebaseKeys.contains(fbKey)) {
            errors.add(_Issue(
              '$childPath.$fbKey',
              '"$fbKey" is not a recognised firebase field. '
              'Valid fields: config_file, project_id, service_account.',
            ));
          }
        }
      }
      _scanForDeprecatedFirebase(entry.value, childPath, errors);
    }
  }

  void _printValidationJson(
    String specPath,
    List<_Issue> errors,
    List<_Issue> warnings, {
    String? parseError,
  }) {
    final errList = parseError != null
        ? [{'severity': 'error', 'path': 'annspec.yaml', 'message': parseError, 'fix': null}]
        : errors.map((e) => {'severity': 'error', 'path': e.path, 'message': e.message, 'fix': null}).toList();

    final warnList = warnings
        .map((w) => {'severity': 'warning', 'path': w.path, 'message': w.message, 'fix': null})
        .toList();

    print(jsonEncode({
      'valid': errList.isEmpty,
      'specPath': p.absolute(specPath),
      'errors': errList,
      'warnings': warnList,
    }));
  }
}

class _Issue {
  final String path;
  final String message;
  const _Issue(this.path, this.message);
}
