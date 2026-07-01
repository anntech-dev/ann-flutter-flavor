import 'package:args/command_runner.dart';
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
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;
    final silent = argResults!['silent'] as bool;

    print('ANN Flavor — syncing $projectRoot\n');

    print('[1/5] Reading annspec.yaml...');
    final spec = AnnspecReader.read(projectRoot);
    print('  ✓ Found ${spec.platforms.length} platform(s).');

    print('\n[2/5] Generating Dart flavor file...');
    DartGenerator.generate(spec, projectRoot);

    print('\n[3/5] Running flutterfire configure (project_id flavors)...');
    await FirebaseGenerator.generate(spec, projectRoot, silent: silent);

    print('\n[4/5] Wiring Android (Gradle plugin + defaultConfig)...');
    AndroidGenerator.generate(projectRoot, spec);

    print('\n[5/5] Wiring iOS (CocoaPods plugin + xcconfig + Info.plist)...');
    IosGenerator.generate(projectRoot, spec);

    if (spec.integrations?.fastlane == true) {
      print('\n[6/?] Setting up Fastlane (Gemfile)...');
      FastlaneGenerator.generate(projectRoot);
    }

    if (spec.integrations?.melos == true) {
      print('\n[7/?] Setting up Melos scripts (pubspec.yaml)...');
      MelosGenerator.generate(projectRoot, spec);
    }

    print('\n✅  Sync complete.');
    print('    iOS: run `pod install` if Podfile changed.');
  }
}
