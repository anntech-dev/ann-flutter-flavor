import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runSync(Directory projectDir) =>
    Process.run('dart', ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path],
        workingDirectory: _packageRoot);

void _writeMinimalSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    fastlane: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');
}

void main() {
  group('ios_generator — Podfile comment', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('podfile_test_');
      _writeMinimalSpec(tempDir);
      // Create a minimal ios/Podfile
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      File('${iosDir.path}/Podfile').writeAsStringSync(
          "platform :ios, '12.0'\n\ntarget 'Runner' do\nend\n");
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('Podfile gets comment before plugin line', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect(content, contains("# Added by ann_flutter_flavor"));
      final commentIdx = content.indexOf('# Added by ann_flutter_flavor');
      final pluginIdx  = content.indexOf("plugin 'ann-ios-flavorize'");
      expect(pluginIdx, greaterThan(commentIdx),
          reason: 'Comment must appear immediately before the plugin line');
      // Ensure they are adjacent (only a newline between them)
      final between = content.substring(commentIdx, pluginIdx);
      expect(between.trim(), equals('# Added by ann_flutter_flavor — multi-flavor iOS build configuration'));
    });

    test('Podfile is not patched twice on re-run', () async {
      await _runSync(tempDir);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect('ann-ios-flavorize'.allMatches(content).length, 1,
          reason: 'Plugin line should appear exactly once');
    });
  });

  group('fastlane_generator — Gemfile comment', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gemfile_test_');
      _writeMinimalSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('new Gemfile contains comment before ann-flavor-flutter gem', () async {
      await _runSync(tempDir);
      final gemfile = File('${tempDir.path}/Gemfile');
      expect(gemfile.existsSync(), isTrue);
      final content = gemfile.readAsStringSync();
      expect(content, contains('# Added by ann_flutter_flavor — Fastlane integration'));
      final commentIdx = content.indexOf('# Added by ann_flutter_flavor — Fastlane integration');
      final gemIdx     = content.indexOf('gem "ann-flavor-flutter"');
      expect(gemIdx, greaterThan(commentIdx),
          reason: 'Comment must appear before the gem line');
    });

    test('existing Gemfile gets comment+gem pair appended', () async {
      File('${tempDir.path}/Gemfile').writeAsStringSync(
          'source "https://rubygems.org"\ngem "fastlane"\n');
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      expect(content, contains('# Added by ann_flutter_flavor — Fastlane integration'));
      expect(content, contains('gem "ann-flavor-flutter"'));
    });

    test('Gemfile is not patched twice on re-run', () async {
      await _runSync(tempDir);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      expect('ann-flavor-flutter'.allMatches(content).length, 1,
          reason: 'gem line should appear exactly once');
    });
  });

  group('android_generator — no applicationId / minSdk patching', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('android_test_');
      _writeMinimalSpec(tempDir);
      // Create a minimal android project structure
      final appDir = Directory('${tempDir.path}/android/app')..createSync(recursive: true);
      File('${appDir.path}/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
}
android {
    defaultConfig {
        applicationId = "com.original.id"
        minSdk = 21
    }
}
''');
      final settingsFile = File('${tempDir.path}/android/settings.gradle.kts');
      settingsFile.writeAsStringSync('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
    }
    plugins {}
}
plugins {}
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('sync does not overwrite applicationId in build.gradle.kts', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
      expect(content, contains('applicationId = "com.original.id"'),
          reason: 'applicationId must not be changed by sync');
    });

    test('sync does not overwrite minSdk in build.gradle.kts', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
      expect(content, contains('minSdk = 21'),
          reason: 'minSdk must not be changed by sync');
    });
  });
}
