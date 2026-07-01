import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../versions.g.dart';

class DoctorCommand extends Command<void> {
  @override
  final name = 'doctor';

  @override
  final description =
      'Show environment health: ann_flutter_flavor version and all linked plugin versions.';

  DoctorCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;

    print('ann_flutter_flavor  $kTargetFlutterVersion');
    print('');

    final rows = _collectRows(projectRoot);

    const colPlugin  = 24;
    const colCurrent = 11;
    const colTarget  = 11;
    // status column is left to overflow naturally

    _printRow('Plugin', 'Current', 'Target', 'Status',
        colPlugin, colCurrent, colTarget, header: true);
    print('─' * (colPlugin + colCurrent + colTarget + 20));

    var hasOutdated = false;
    for (final row in rows) {
      _printRow(row.plugin, row.current, row.target, row.status,
          colPlugin, colCurrent, colTarget);
      if (row.status.startsWith('⚠')) hasOutdated = true;
    }
    print('');

    exitCode = hasOutdated ? 1 : 0;
  }

  // ── Row collection ─────────────────────────────────────────────────────────

  List<_VersionRow> _collectRows(String projectRoot) => [
    _checkFlutter(projectRoot),
    _checkGradle(projectRoot),
    _checkCocoapods(projectRoot),
    _checkFastlane(projectRoot),
    _studioRow(),
  ];

  _VersionRow _checkFlutter(String root) {
    final lockFile = File(p.join(root, 'pubspec.lock'));
    if (!lockFile.existsSync()) {
      return _VersionRow('Flutter package', null, kTargetFlutterVersion,
          reason: 'pubspec.lock not found');
    }
    final content = lockFile.readAsStringSync();
    final match = RegExp(
            r'ann_flutter_flavor:[\s\S]*?version:\s*"([^"]+)"')
        .firstMatch(content);
    return _VersionRow('Flutter package', match?.group(1), kTargetFlutterVersion);
  }

  _VersionRow _checkGradle(String root) {
    File? file;
    for (final name in ['settings.gradle.kts', 'settings.gradle']) {
      final f = File(p.join(root, 'android', name));
      if (f.existsSync()) { file = f; break; }
    }
    if (file == null) {
      return _VersionRow('Gradle plugin', null, kTargetGradleVersion,
          reason: 'android/settings.gradle.kts not found');
    }
    final match = RegExp(
            r'id\("dev\.anntech\.flavorize"\)\s+version\s+"([^"]+)"')
        .firstMatch(file.readAsStringSync());
    return _VersionRow('Gradle plugin', match?.group(1), kTargetGradleVersion);
  }

  _VersionRow _checkCocoapods(String root) {
    File? file;
    for (final candidate in [
      p.join(root, 'Gemfile.lock'),
      p.join(root, 'ios', 'Gemfile.lock'),
    ]) {
      final f = File(candidate);
      if (f.existsSync()) { file = f; break; }
    }
    if (file == null) {
      return _VersionRow('CocoaPods plugin', null, kTargetCocoapodsVersion,
          reason: 'Gemfile.lock not found');
    }
    final match = RegExp(r'ann-flavor-cocoapods \(([^)]+)\)')
        .firstMatch(file.readAsStringSync());
    return _VersionRow('CocoaPods plugin', match?.group(1), kTargetCocoapodsVersion);
  }

  _VersionRow _checkFastlane(String root) {
    final file = File(p.join(root, 'Gemfile.lock'));
    if (!file.existsSync()) {
      return _VersionRow('Fastlane plugin', null, kTargetFastlaneVersion,
          reason: 'Gemfile.lock not found');
    }
    final content = file.readAsStringSync();
    final match = RegExp(r'ann-flavor-fastlane \(([^)]+)\)')
            .firstMatch(content) ??
        RegExp(r'annai-flutter-flavor \(([^)]+)\)').firstMatch(content);
    return _VersionRow('Fastlane plugin', match?.group(1), kTargetFastlaneVersion);
  }

  _VersionRow _studioRow() => _VersionRow.notDetectable('Studio plugin', kTargetStudioVersion);

  // ── Output ─────────────────────────────────────────────────────────────────

  void _printRow(
    String plugin,
    String current,
    String target,
    String status,
    int colPlugin,
    int colCurrent,
    int colTarget, {
    bool header = false,
  }) {
    final p1 = plugin.padRight(colPlugin);
    final p2 = current.padRight(colCurrent);
    final p3 = target.padRight(colTarget);
    print('$p1$p2$p3$status');
  }
}

// ── Data ────────────────────────────────────────────────────────────────────

class _VersionRow {
  final String plugin;
  final String current;
  final String target;
  final String status;

  _VersionRow(this.plugin, String? currentVersion, this.target, {String? reason})
      : current = currentVersion ?? '–',
        status  = currentVersion == null
            ? (reason != null ? 'ℹ n/a ($reason)' : '✗ not found')
            : _computeStatus(currentVersion, target);

  _VersionRow.notDetectable(this.plugin, this.target)
      : current = '–',
        status  = 'ℹ not detectable';

  static String _computeStatus(String current, String target) {
    final cmp = _compareSemver(current, target);
    if (cmp == 0) return '✅ ok';
    if (cmp < 0)  return '⚠ outdated';
    return '⚠ newer';
  }

  static int _compareSemver(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
