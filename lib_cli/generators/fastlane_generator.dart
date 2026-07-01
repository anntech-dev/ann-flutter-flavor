import 'dart:io';
import 'package:path/path.dart' as p;

class FastlaneGenerator {
  static const _requiredLines = [
    'source "https://rubygems.org"',
    'gem "fastlane"',
    // gem "ann-flavor-flutter" handled separately — needs a comment prefix
  ];

  static const _annGemLine     = 'gem "ann-flavor-flutter"';
  static const _annGemComment  = '# Added by ann_flutter_flavor — Fastlane integration';

  static void generate(String projectRoot) {
    final file = File(p.join(projectRoot, 'Gemfile'));

    if (!file.existsSync()) {
      final content = [
        ..._requiredLines,
        _annGemComment,
        _annGemLine,
      ].join('\n') + '\n';
      file.writeAsStringSync(content);
      print('  ✅ Gemfile created');
      return;
    }

    var existing = file.readAsStringSync();
    var changed = false;

    final missingLines = _requiredLines.where((l) => !existing.contains(l)).toList();
    if (missingLines.isNotEmpty) {
      existing = existing.trimRight() + '\n' + missingLines.join('\n') + '\n';
      changed = true;
    }

    if (!existing.contains(_annGemLine)) {
      existing = existing.trimRight() + '\n$_annGemComment\n$_annGemLine\n';
      changed = true;
    }

    if (!changed) {
      print('  ✅ Gemfile already up to date');
      return;
    }

    file.writeAsStringSync(existing);
    print('  ✅ Gemfile updated');
  }
}
