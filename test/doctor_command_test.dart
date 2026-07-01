import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

void main() {
  group('doctor command', () {
    test('prints version header and plugin table', () async {
      final result = await Process.run(
        'dart',
        ['run', 'ann_flutter_flavor', 'doctor'],
        workingDirectory: _packageRoot,
      );
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      expect(result.stdout.toString(), contains('ann_flutter_flavor'));
      expect(result.stdout.toString(), contains('Flutter package'));
      expect(result.stdout.toString(), contains('Gradle plugin'));
      expect(result.stdout.toString(), contains('Studio plugin'));
    });

    test('version command is no longer recognised', () async {
      final result = await Process.run(
        'dart',
        ['run', 'ann_flutter_flavor', 'version'],
        workingDirectory: _packageRoot,
      );
      // args package prints "Could not find a command named" and exits 0
      final output = result.stdout.toString() + result.stderr.toString();
      expect(output, contains('Could not find a command named'));
      expect(output, isNot(contains('Show ann_flutter_flavor version')),
          reason: 'old VersionCommand description should be absent');
      expect(result.stdout.toString(), contains('doctor'),
          reason: 'doctor should appear in the available commands list');
    });
  });
}
