import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../spec/annspec_reader.dart';
import '../model/annspec_model.dart';

const _labelW = 10;
final _divider = '─' * 52;

class SummaryCommand extends Command<void> {
  @override
  final name = 'summary';

  @override
  final description =
      'Show the fully resolved annspec.yaml — merged values per flavor and build type.';

  SummaryCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;

    AnnspecModel spec;
    try {
      spec = AnnspecReader.read(projectRoot);
    } catch (e) {
      print('✗ $e');
      return;
    }

    print('');
    print('ANN Flavor — resolved summary');
    print(_divider);
    print('  ${p.join(projectRoot, 'annspec.yaml')}');

    for (final platform in spec.platforms) {
      print('');
      print('');
      _printPlatform(platform);
    }
    print('');
  }

  // ── Platform ───────────────────────────────────────────────────────────────

  void _printPlatform(AnnspecPlatform plat) {
    print(plat.key.toUpperCase());

    if (plat.flavors.isEmpty) {
      _printDefaultBuildTypes(plat);
    } else {
      for (final flavor in plat.flavors) {
        print('');
        _printFlavor(flavor, plat);
      }
    }
  }

  // ── No-flavor case: show default resolved per build type ───────────────────

  void _printDefaultBuildTypes(AnnspecPlatform plat) {
    final buildTypeKeys = _allBuildTypeKeys(
      plat.defaultBuildTypes.keys,
      hasFirebaseRelease: plat.defaultFirebaseRelease != null,
      hasFirebaseDebug:   plat.defaultFirebaseDebug != null,
    );

    for (final bt in buildTypeKeys) {
      final btCfg = plat.defaultBuildTypes[bt];
      print('');
      print('  $bt');

      // id
      final id = (plat.baseId ?? '') + (btCfg?.idSuffix ?? '');
      if (id.isNotEmpty) _row('id', id);

      // name
      final name = (plat.baseName ?? '') + (btCfg?.nameSuffix ?? '');
      if (name.isNotEmpty) _row('name', name);

      // version (same across build types)
      if (plat.defaultVersionName != null)
        _row('version', _versionStr(plat.defaultVersionName, plat.defaultVersionCode));

      // firebase
      final fb = bt == 'release' ? plat.defaultFirebaseRelease : plat.defaultFirebaseDebug;
      _printFirebase(fb);

      // auth
      final auth = bt == 'release' ? plat.defaultAuthRelease : plat.defaultAuthDebug;
      _printAuth(auth);

      // admob
      final admob = btCfg?.gmsAdsId ?? plat.defaultGmsAdsId;
      if (admob != null) _row('admob', admob);

      // android-only build type fields
      _printAndroidBtFields(btCfg);
    }
  }

  // ── Flavor case ────────────────────────────────────────────────────────────

  void _printFlavor(AnnspecFlavor f, AnnspecPlatform plat) {
    print('  ── ${f.key} $_divider'.substring(0, _divider.length + 5));

    final buildTypeKeys = _allBuildTypeKeys(
      f.buildTypes.keys,
      hasFirebaseRelease: (f.firebaseRelease ?? plat.defaultFirebaseRelease) != null,
      hasFirebaseDebug:   (f.firebaseDebug   ?? plat.defaultFirebaseDebug)   != null,
    );

    for (final bt in buildTypeKeys) {
      final btCfg = f.buildTypes[bt];
      print('');
      print('  $bt');

      // id — baseId + flavor.idSuffix + buildType.idSuffix
      final baseId = f.id ?? (plat.baseId ?? '');
      final id = f.id != null
          ? baseId + (btCfg?.idSuffix ?? '')
          : baseId + (f.idSuffix ?? '') + (btCfg?.idSuffix ?? '');
      if (id.isNotEmpty) _row('id', id);

      // name — (flavor.name ?? default.name) + buildType.nameSuffix
      final baseName = f.name ?? plat.baseName ?? '';
      final name = baseName + (btCfg?.nameSuffix ?? '');
      if (name.isNotEmpty) _row('name', name);

      // version — flavor overrides default, same across build types
      final vn = f.versionName ?? plat.defaultVersionName;
      final vc = f.versionCode ?? plat.defaultVersionCode;
      if (vn != null) _row('version', _versionStr(vn, vc));

      // firebase — flavor build_type → default build_type
      final fb = bt == 'release'
          ? (f.firebaseRelease ?? plat.defaultFirebaseRelease)
          : (f.firebaseDebug   ?? plat.defaultFirebaseDebug);
      _printFirebase(fb);

      // auth — same cascade
      final auth = bt == 'release'
          ? (f.authRelease ?? plat.defaultAuthRelease)
          : (f.authDebug   ?? plat.defaultAuthDebug);
      _printAuth(auth);

      // admob — buildType.admob → flavor.admob → default.admob
      final admob = btCfg?.gmsAdsId ?? f.gmsAdsId ?? plat.defaultGmsAdsId;
      if (admob != null) _row('admob', admob);

      // stores (not build-type-specific)
      _printStores(f);

      // custom — already fully resolved per build type
      _printCustom(f.customByBuildType[bt] ?? {});

      // android-only build type fields
      _printAndroidBtFields(btCfg);
    }
  }

  // ── Field renderers ────────────────────────────────────────────────────────

  String _versionStr(String? name, String? code) =>
      code != null ? '$name ($code)' : name ?? '';

  void _printFirebase(AnnspecFirebase? fb) {
    if (fb == null) return;
    if (fb.configFile != null) _row('firebase', 'config_file → ${fb.configFile}');
    if (fb.projectId != null) _row('firebase', 'project → ${fb.projectId}');
  }

  void _printAuth(AnnspecAuth? auth) {
    if (auth == null) return;
    if (auth.clientId != null)         _row('auth', 'clientId          ${auth.clientId}');
    if (auth.reversedClientId != null) _cont('     reversedClientId  ${auth.reversedClientId}');
  }

  void _printStores(AnnspecFlavor f) {
    final lines = <String>[];
    if (f.googlePlayPriority != null) lines.add('google_play    priority ${f.googlePlayPriority}');
    if (f.samsungAppId != null)       lines.add('samsung_galaxy app_id   ${f.samsungAppId}');
    if (f.amazonAppId != null)        lines.add('amazon         app_id   ${f.amazonAppId}');
    if (f.appleId != null)            lines.add('app_store      apple_id ${f.appleId}');
    if (lines.isEmpty) return;
    _row('stores', lines.first);
    for (final l in lines.skip(1)) _cont(l);
  }

  void _printCustom(Map<String, Map<String, dynamic>> custom) {
    if (custom.isEmpty) return;
    bool first = true;
    for (final group in custom.entries) {
      if (first) { _row('custom', group.key); first = false; }
      else        _cont(group.key);
      for (final kv in group.value.entries) {
        final val = kv.value is List
            ? '[${(kv.value as List).join(', ')}]'
            : '${kv.value}';
        _cont('  ${kv.key.padRight(16)} $val');
      }
    }
  }

  void _printAndroidBtFields(AnnspecBuildTypeConfig? btCfg) {
    if (btCfg == null) return;
    if (btCfg.minifyEnabled != null)
      _row('minify', '${btCfg.minifyEnabled}  shrink: ${btCfg.shrinkResources ?? false}');
    if (btCfg.ndkVersion != null)
      _row('ndk', btCfg.ndkVersion!);
    if (btCfg.ndkAbiFilters.isNotEmpty)
      _row('abi', btCfg.ndkAbiFilters.join(', '));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns an ordered, deduplicated list of build type keys to display.
  /// Always puts release before debug; appends any others alphabetically.
  List<String> _allBuildTypeKeys(
    Iterable<String> fromBuildTypes, {
    bool hasFirebaseRelease = false,
    bool hasFirebaseDebug   = false,
  }) {
    final all = <String>{};
    if (hasFirebaseRelease) all.add('release');
    if (hasFirebaseDebug)   all.add('debug');
    all.addAll(fromBuildTypes);
    if (all.isEmpty) { all.add('release'); all.add('debug'); }

    final ordered = <String>[];
    if (all.contains('release')) ordered.add('release');
    if (all.contains('debug'))   ordered.add('debug');
    for (final k in all) {
      if (k != 'release' && k != 'debug') ordered.add(k);
    }
    return ordered;
  }

  // ── Print helpers ──────────────────────────────────────────────────────────

  void _row(String label, String value) =>
      print('    ${label.padRight(_labelW)}  $value');

  void _cont(String value) =>
      print('    ${''.padRight(_labelW)}  $value');
}
