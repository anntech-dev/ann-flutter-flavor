import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

// ── helpers ──────────────────────────────────────────────────────────────────

Future<ProcessResult> _runValidate(Directory dir) => Process.run(
      'dart',
      ['run', 'ann_flutter_flavor', 'validate', '--project', dir.path],
      workingDirectory: _packageRoot,
    );

void _writeSpec(Directory dir, {String androidFirebase = '', String iosFirebase = ''}) =>
    File('${dir.path}/annspec.yaml').writeAsStringSync(
        _spec(androidFirebase: androidFirebase, iosFirebase: iosFirebase));

/// Minimal platform block shared by all tests. The firebase section is
/// injected via [androidFirebase] / [iosFirebase].
String _spec({
  String androidFirebase = '',
  String iosFirebase = '',
}) =>
    '''
enabled: true
app:
  integrations:
    firebase: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
      $androidFirebase
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
  ios:
    default:
      id: com.example.test
      $iosFirebase
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''';

bool _hasServiceAccountWarning(String output) =>
    output.contains('no "service_account" resolves');

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  setUp(() => tempDir = Directory.systemTemp.createTempSync('sa_cascade_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  group('service_account cascade — level 4: default.firebase.service_account', () {
    test('resolves for default build types — no warning', () async {
      _writeSpec(tempDir, androidFirebase: '''
firebase:
        service_account: "keys/sa.json"
      build_types:
        release:
          firebase:
            project_id: "proj-prod"
        debug:
          firebase:
            project_id: "proj-dev"''', iosFirebase: '''
firebase:
        service_account: "keys/sa.json"
      build_types:
        release:
          firebase:
            project_id: "proj-prod"''');
      final result = await _runValidate(tempDir);
      expect(_hasServiceAccountWarning('${result.stdout}${result.stderr}'), isFalse,
          reason: 'default.firebase.service_account should suppress the warning\n'
              'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    });

    test('resolves for flavor build types — no warning', () async {
      _writeSpec(tempDir, androidFirebase: '''
firebase:
        service_account: "keys/sa.json"
      build_types:
        release:
          firebase:
            project_id: "proj-prod"''', iosFirebase: '');
      final result = await _runValidate(tempDir);
      expect(_hasServiceAccountWarning('${result.stdout}${result.stderr}'), isFalse,
          reason: 'default.firebase.service_account should cover flavor build types too');
    });
  });

  group('service_account cascade — level 3: default.build_types.<bt>.firebase.service_account', () {
    test('resolves — no warning', () async {
      _writeSpec(tempDir, androidFirebase: '''
build_types:
        release:
          firebase:
            project_id: "proj-prod"
            service_account: "keys/sa.json"
        debug:
          firebase:
            project_id: "proj-dev"
            service_account: "keys/sa.json"''', iosFirebase: '');
      final result = await _runValidate(tempDir);
      expect(_hasServiceAccountWarning('${result.stdout}${result.stderr}'), isFalse,
          reason: 'service_account inside build_types firebase block should resolve');
    });
  });

  group('service_account cascade — level 2: flavor.firebase.service_account', () {
    test('resolves for that flavor — no warning', () async {
      // project_id only at flavor level (no default project_id, so no default warning).
      // service_account only at flavor.firebase level (not inside build_types).
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        firebase:
          service_account: "keys/sa.json"
        build_types:
          release:
            firebase:
              project_id: "proj-flavor-prod"
          debug:
            firebase:
              project_id: "proj-flavor-dev"
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');
      final result = await _runValidate(tempDir);
      expect(_hasServiceAccountWarning('${result.stdout}${result.stderr}'), isFalse,
          reason: 'flavor.firebase.service_account should resolve for that flavor\n'
              'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    });
  });

  group('service_account cascade — no service_account at any level', () {
    test('warning fires when project_id is set but no service_account resolves', () async {
      _writeSpec(tempDir, androidFirebase: '''
build_types:
        release:
          firebase:
            project_id: "proj-prod"''', iosFirebase: '');
      final result = await _runValidate(tempDir);
      expect(_hasServiceAccountWarning('${result.stdout}${result.stderr}'), isTrue,
          reason: 'Missing service_account should produce a warning');
    });
  });
}
