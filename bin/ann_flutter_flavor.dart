import 'package:args/command_runner.dart';
import '../lib_cli/commands/sync_command.dart';
import '../lib_cli/commands/validate_command.dart';
import '../lib_cli/commands/firebase_command.dart';
import '../lib_cli/commands/summary_command.dart';
import '../lib_cli/commands/doctor_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'ann_flutter_flavor',
    'ANN Flutter Flavor — manage flavors across Android, iOS, Web and Windows.',
  )
    ..addCommand(SyncCommand())
    ..addCommand(ValidateCommand())
    ..addCommand(FirebaseCommand())
    ..addCommand(SummaryCommand())
    ..addCommand(DoctorCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    print(e);
  }
}
