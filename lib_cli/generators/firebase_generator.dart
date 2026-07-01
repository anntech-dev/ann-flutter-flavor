import 'dart:async';
import 'dart:io';
import '../model/annspec_model.dart';

/// Runs `flutterfire configure` for every flavor × platform × build type
/// that has a project_id in the annspec.yaml.
class FirebaseGenerator {
  static const _buildTypes = ['release', 'debug'];
  static const _platforms  = ['android', 'ios', 'web', 'windows'];

  // Kill flutterfire if it hasn't finished within this window.
  // Auth prompts or network issues cause it to hang indefinitely otherwise.
  static const _timeout = Duration(seconds: 120);

  static bool _reauthed = false;

  /// [silent] — when true (Studio plugin), skip interactive reauth and print
  /// instructions instead. When false (CLI), attempt gcloud/firebase reauth.
  static Future<void> generate(
    AnnspecModel spec,
    String projectRoot, {
    bool silent = false,
  }) async {
    final cmds = _buildCommands(spec);

    if (cmds.isEmpty) {
      print('  ⚠ No Firebase project_id found in annspec.yaml — skipping flutterfire.');
      return;
    }

    // In CLI mode, verify credentials exist before running any commands.
    if (!silent && !_hasCredentials()) {
      print('  🔑 GOOGLE_APPLICATION_CREDENTIALS not set — running gcloud auth application-default login...');
      final ok = await _gcloudLogin();
      if (!ok) {
        print('  ✗ Authentication failed. Set GOOGLE_APPLICATION_CREDENTIALS or run:');
        print('       gcloud auth application-default login');
        print('       firebase login --reauth');
        return;
      }
      _reauthed = true;
    }

    print('  Running flutterfire configure for ${cmds.length} combination(s)...');
    var failed = 0;

    for (final cmd in cmds) {
      print('  ▶ ${cmd.label}');
      final result = await _runWithReauth(cmd, projectRoot, silent: silent);
      if (result == _RunResult.success) {
        print('  ✓ Done: ${cmd.label}');
      } else {
        print('  ✗ Failed: ${cmd.label}');
        failed++;
      }
    }

    if (failed > 0) {
      print('  ⚠ $failed flutterfire command(s) failed.');
    } else {
      print('  ✓ Firebase options files generated.');
    }
  }

  static Future<_RunResult> _runWithReauth(
    _FbCmd cmd,
    String projectRoot, {
    required bool silent,
  }) async {
    final result = await _runFlutterfire(cmd, projectRoot);

    if (result == _RunResult.success) return result;

    if (result == _RunResult.authError) {
      if (silent) {
        // Studio plugin: show actionable message, do not block with a browser flow.
        print('  ⚠ Firebase credentials invalid or expired.');
        print('     Fix in a terminal then re-run Sync Spec:');
        print('       gcloud auth application-default login');
        print('       — or —');
        print('       firebase login --reauth');
        return _RunResult.failure;
      }

      // CLI: attempt reauth once then retry.
      if (!_reauthed) {
        print('  🔑 Firebase credentials invalid or expired — running gcloud auth application-default login...');
        final loginOk = await _gcloudLogin();
        _reauthed = true;
        if (loginOk) {
          print('  ↩ Retrying: ${cmd.label}');
          return _runFlutterfire(cmd, projectRoot);
        }
        print('  ✗ gcloud login failed. Try: firebase login --reauth');
      }
    }

    return result;
  }

  static Future<_RunResult> _runFlutterfire(_FbCmd cmd, String projectRoot) async {
    ProcessResult result;
    try {
      result = await Process.run(
        'flutterfire',
        _buildArgs(cmd),
        workingDirectory: projectRoot,
      ).timeout(_timeout, onTimeout: () {
        print('  ✗ Timed out after ${_timeout.inSeconds}s: ${cmd.label}');
        return ProcessResult(-1, 1, '', '__timeout__');
      });
    } on ProcessException catch (e) {
      print('  ✗ Could not run flutterfire: ${e.message}');
      print('     Install it with: dart pub global activate flutterfire_cli');
      return _RunResult.failure;
    }

    if (result.exitCode == 0) return _RunResult.success;

    final errText = result.stderr.toString();

    if (errText == '__timeout__' || _isAuthError(errText)) {
      if (errText != '__timeout__') stderr.write(errText);
      return _RunResult.authError;
    }

    stderr.write(errText);
    return _RunResult.failure;
  }

  static bool _hasCredentials() {
    // Check explicit service account file
    final path = Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
    if (path != null && path.isNotEmpty) {
      final f = File(path);
      return f.existsSync() && f.lengthSync() > 0;
    }
    // Fall back to gcloud ADC default location
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final adcFile = File('$home/.config/gcloud/application_default_credentials.json');
    return adcFile.existsSync() && adcFile.lengthSync() > 0;
  }

  /// Runs `gcloud auth application-default login` with stdio inherited so the browser flow works.
  static Future<bool> _gcloudLogin() async {
    try {
      final process = await Process.start(
        'gcloud',
        ['auth', 'application-default', 'login'],
        mode: ProcessStartMode.inheritStdio,
      );
      final exitCode = await process.exitCode;
      return exitCode == 0;
    } on ProcessException catch (e) {
      print('  ✗ Could not run gcloud: ${e.message}');
      print('     Install it from https://cloud.google.com/sdk/docs/install');
      return false;
    }
  }

  static bool _isAuthError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('unauthenticated') ||
        lower.contains('invalid_grant') ||
        lower.contains('token') && (lower.contains('expired') || lower.contains('revoked')) ||
        lower.contains('authentication required') ||
        lower.contains('not logged in') ||
        lower.contains('please sign in') ||
        lower.contains('failed to get project') ||
        lower.contains('permission denied');
  }

  // ── Command builder ──────────────────────────────────────────────────────────

  static List<_FbCmd> _buildCommands(AnnspecModel spec) {
    final cmds = <_FbCmd>[];

    for (final platformKey in _platforms) {
      final platform = spec.platform(platformKey);
      if (platform == null) continue;

      for (final flavor in platform.flavors) {
        for (final buildType in _buildTypes) {
          final fb = buildType == 'release'
              ? (flavor.firebaseRelease ?? platform.defaultFirebaseRelease)
              : (flavor.firebaseDebug   ?? platform.defaultFirebaseDebug);

          if (fb?.projectId == null) continue;

          final outFile =
              'lib/generated/firebase/${flavor.key}_${buildType}_${platformKey}_firebase_options.dart';

          cmds.add(_FbCmd(
            projectId: fb!.projectId!,
            outFile:   outFile,
            platform:  platformKey,
            label:     '${flavor.key} / $buildType / $platformKey',
          ));
        }
      }
    }
    return cmds;
  }

  static List<String> _buildArgs(_FbCmd cmd) => [
    'configure',
    '-y',
    '-f',
    '-p', cmd.projectId,
    '-o', cmd.outFile,
    '--platforms=${cmd.platform}',
  ];
}

class _FbCmd {
  final String projectId;
  final String outFile;
  final String platform;
  final String label;

  const _FbCmd({
    required this.projectId,
    required this.outFile,
    required this.platform,
    required this.label,
  });
}

enum _RunResult { success, authError, failure }
