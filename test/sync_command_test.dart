import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

// Creates a minimal valid annspec.yaml in a temp directory.
void _writeValidSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
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
}

// Creates an annspec.yaml with an unknown firebase field (pre-flight should catch it).
void _writeInvalidSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        build_types:
          release:
            firebase:
              firebase_app_id: "1:111:android:abc"
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
}

Future<ProcessResult> _runSync(Directory projectDir, List<String> extraArgs) {
  return Process.run(
    'dart',
    ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path, ...extraArgs],
    workingDirectory: _packageRoot,
  );
}

void main() {
  group('sync command — pre-flight validation', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('sync_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('aborts with exit 1 and no generators called when spec has errors', () async {
      _writeInvalidSpec(tempDir);
      final result = await _runSync(tempDir, []);
      expect(result.exitCode, 1,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      // Dart file must NOT be generated since pre-flight aborted
      final dartOut = File('${tempDir.path}/lib/generated/ann_flavor.g.dart');
      expect(dartOut.existsSync(), isFalse);
    });

    test('--format json emits JSON on stdout and exits 1 on errors', () async {
      _writeInvalidSpec(tempDir);
      final result = await _runSync(tempDir, ['--format', 'json']);
      expect(result.exitCode, 1,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      // stdout must be valid JSON
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
      } catch (e) {
        fail('stdout was not valid JSON: ${result.stdout}');
      }
      expect(json['valid'], isFalse);
      expect(json['errors'], isA<List>());
      expect((json['errors'] as List).isNotEmpty, isTrue);
    });

    test('--format json stdout is not polluted by step messages', () async {
      _writeInvalidSpec(tempDir);
      final result = await _runSync(tempDir, ['--format', 'json']);
      final stdout = result.stdout.toString().trim();
      expect(stdout, isNotEmpty, reason: 'stdout should contain JSON');
      // Must decode as a single JSON object with no extra text
      expect(() => jsonDecode(stdout), returnsNormally,
          reason: 'stdout should be valid JSON only, got: $stdout');
    });
  });

  group('sync command — step order', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('sync_order_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('step labels [0/6] through [3/6] appear in ascending order in output', () async {
      _writeValidSpec(tempDir);
      final result = await _runSync(tempDir, []);
      final stdout = result.stdout.toString();
      final positions = [
        stdout.indexOf('[0/6]'),
        stdout.indexOf('[1/6]'),
        stdout.indexOf('[2/6]'),
        stdout.indexOf('[3/6]'),
      ];
      for (var i = 0; i < positions.length; i++) {
        expect(positions[i], greaterThan(-1),
            reason: 'Step [${i}/6] label not found in output:\n$stdout');
      }
      for (var i = 0; i < positions.length - 1; i++) {
        expect(positions[i], lessThan(positions[i + 1]),
            reason: 'Step $i appeared after step ${i + 1}');
      }
    });

    test('[2/6] Android appears before [3/6] iOS', () async {
      _writeValidSpec(tempDir);
      final result = await _runSync(tempDir, []);
      final stdout = result.stdout.toString();
      expect(stdout.indexOf('[2/6]'), lessThan(stdout.indexOf('[3/6]')),
          reason: 'Android (step 2) must precede iOS (step 3):\n$stdout');
    });

    test('[3/6] iOS appears before [4/6] Firebase', () async {
      _writeValidSpec(tempDir);
      final result = await _runSync(tempDir, []);
      final stdout = result.stdout.toString();
      expect(stdout.indexOf('[3/6]'), lessThan(stdout.indexOf('[4/6]')),
          reason: 'iOS (step 3) must precede Firebase (step 4):\n$stdout');
    });
  });
}
