import 'package:args/command_runner.dart';
import '../generators/firebase_generator.dart';
import '../spec/annspec_reader.dart';

/// Runs flutterfire configure for every project_id entry in annspec.yaml.
class FirebaseCommand extends Command<void> {
  @override
  final name = 'firebase';

  @override
  final description =
      'Run flutterfire configure for every build type that has a project_id '
      'in annspec.yaml. Requires Application Default Credentials (ADC).';

  FirebaseCommand() {
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Flutter project root.',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;

    print('ANN Flavor — running flutterfire configure for $projectRoot');
    final spec = AnnspecReader.read(projectRoot);

    await FirebaseGenerator.generate(spec, projectRoot);
  }
}
