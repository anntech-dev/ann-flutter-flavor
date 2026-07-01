import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';
// AnnspecBuildTypeConfig is defined in annspec_model.dart

class AnnspecReader {
  static AnnspecModel read(String projectRoot) {
    final file = File(p.join(projectRoot, 'annspec.yaml'));
    if (!file.existsSync()) {
      throw Exception('annspec.yaml not found at ${file.path}');
    }
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    if (doc['app'] == null) {
      final hint = doc['annai_app'] != null
          ? '\n  Hint: rename the root key from "annai_app:" to "app:" — the key was changed in v0.2.0.'
          : '\n  annspec.yaml must have a top-level "app:" key containing android/ios/web/windows sections.';
      throw Exception('annspec.yaml is missing the required "app:" root key.$hint');
    }
    final app = doc['app'] as YamlMap;
    final platforms = <AnnspecPlatform>[];

    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      final platformMap = app[platformKey] as YamlMap?;
      if (platformMap == null) continue;
      platforms.add(_parsePlatform(platformKey, platformMap));
    }

    final integrationsMap = app['integrations'] as YamlMap?;
    final integrations = integrationsMap != null
        ? AnnspecIntegrations(
            fastlane: integrationsMap['fastlane'] as bool? ?? false,
            melos:    integrationsMap['melos']    as bool? ?? false,
            firebase: integrationsMap['firebase'] as bool? ?? false,
          )
        : null;

    return AnnspecModel(platforms: platforms, integrations: integrations);
  }

  static AnnspecPlatform _parsePlatform(String key, YamlMap map) {
    final defaultMap = map['default'] as YamlMap?;
    final flavorMap = map['flavor'] as YamlMap?;
    final credentialsMap = defaultMap?['credentials'] as YamlMap?;
    final sdkMap = defaultMap?['sdk'] as YamlMap?;

    final defaultBuildTypes = _parseBuildTypes(defaultMap?['build_types']);
    final defaultCustom = _parseCustomMap(defaultMap?['custom']);
    final defaultCustomByBt = _parseCustomPerBuildType(defaultMap?['build_types']);
    return AnnspecPlatform(
      key: key,
      baseId: defaultMap?['id'] as String?,
      baseName: defaultMap?['name'] as String?,
      defaultVersionName: defaultMap?['version_name']?.toString(),
      defaultVersionCode: defaultMap?['version_code']?.toString(),
      defaultGmsAdsId: (defaultMap?['admob'] as Map?)?['gms_ads_id'] as String?,
      teamId: (credentialsMap?['signing'] as Map?)?['team_id'] as String?,
      defaultFirebaseRelease: _parseFirebase(defaultMap?['build_types']?['release']?['firebase']),
      defaultFirebaseDebug: _parseFirebase(defaultMap?['build_types']?['debug']?['firebase']),
      defaultServiceAccount: (defaultMap?['firebase'] as YamlMap?)?['service_account'] as String?,
      defaultAuthRelease: _parseAuth(defaultMap?['build_types']?['release']?['auth']),
      defaultAuthDebug: _parseAuth(defaultMap?['build_types']?['debug']?['auth']),
      flavors: flavorMap != null ? _parseFlavors(flavorMap, defaultBuildTypes,
          defaultCustom: defaultCustom, defaultCustomByBuildType: defaultCustomByBt) : [],
      minSdk: sdkMap?['minSdk'] as int?,
      signingKeyFile: (credentialsMap?['signing'] as Map?)?['key_file'] as String?,
      googlePlayApiKey: (credentialsMap?['google_play'] as Map?)?['api_key'] as String?,
      appStoreApiKey: (credentialsMap?['app_store'] as Map?)?['api_key'] as String?,
      appStoreExportPlist: (credentialsMap?['app_store'] as Map?)?['export_options_plist'] as String?,
      defaultBuildTypes: defaultBuildTypes,
    );
  }

  static List<AnnspecFlavor> _parseFlavors(
      YamlMap map, Map<String, AnnspecBuildTypeConfig> defaultBuildTypes,
      {Map<String, Map<String, dynamic>> defaultCustom = const {},
       Map<String, Map<String, Map<String, dynamic>>> defaultCustomByBuildType = const {}}) {
    return map.entries.map((e) {
      final key = e.key as String;
      final fm = e.value as YamlMap;
      final flavorBuildTypes = _parseBuildTypes(fm['build_types']);
      final mergedBuildTypes = {...defaultBuildTypes, ...flavorBuildTypes};
      final flavorCustom = _parseCustomMap(fm['custom']);
      final flavorCustomByBt = _parseCustomPerBuildType(fm['build_types']);
      final allBts = {...defaultBuildTypes.keys, ...flavorBuildTypes.keys};
      final customByBuildType = <String, Map<String, Map<String, dynamic>>>{};
      for (final bt in allBts) {
        customByBuildType[bt] = _mergeCustom(
          _mergeCustom(
            _mergeCustom(defaultCustom, defaultCustomByBuildType[bt] ?? const {}),
            flavorCustom,
          ),
          flavorCustomByBt[bt] ?? const {},
        );
      }
      if (customByBuildType.isEmpty) {
        final merged = _mergeCustom(defaultCustom.cast(), flavorCustom);
        if (merged.isNotEmpty) {
          customByBuildType['release'] = merged;
          customByBuildType['debug']   = merged;
        }
      }
      return AnnspecFlavor(
        key: key,
        id: fm['id'] as String?,
        idSuffix: fm['id_suffix'] as String?,
        name: fm['name'] as String?,
        mainFile: fm['main_file'] as String?,
        versionName: fm['version_name']?.toString(),
        versionCode: fm['version_code']?.toString(),
        gmsAdsId: (fm['admob'] as Map?)?['gms_ads_id'] as String?,
        firebaseRelease: _parseFirebase(fm['build_types']?['release']?['firebase']),
        firebaseDebug: _parseFirebase(fm['build_types']?['debug']?['firebase']),
        flavorServiceAccount: (fm['firebase'] as YamlMap?)?['service_account'] as String?,
        authRelease: _parseAuth(fm['build_types']?['release']?['auth']),
        authDebug: _parseAuth(fm['build_types']?['debug']?['auth']),
        googlePlayPriority: fm['stores']?['google_play']?['priority']?.toString(),
        samsungAppId: fm['stores']?['samsung_galaxy']?['app_id']?.toString(),
        amazonAppId: fm['stores']?['amazon']?['app_id']?.toString(),
        appleId: fm['stores']?['app_store']?['apple_id']?.toString(),
        buildTypes: mergedBuildTypes,
        customByBuildType: customByBuildType,
      );
    }).toList();
  }

  static Map<String, AnnspecBuildTypeConfig> _parseBuildTypes(dynamic raw) {
    if (raw == null) return {};
    final m = raw as YamlMap;
    return Map.fromEntries(m.entries.map((e) {
      final key = e.key as String;
      final cfg = e.value as YamlMap? ?? YamlMap();
      final admob = cfg['admob'] as Map?;
      final ndkRaw = cfg['ndkAbiFilters'];
      return MapEntry(key, AnnspecBuildTypeConfig(
        idSuffix:               cfg['id_suffix'] as String?,
        nameSuffix:             cfg['name_suffix'] as String?,
        gmsAdsId:               admob?['gms_ads_id'] as String?,
        minifyEnabled:          cfg['minifyEnabled'] as bool?,
        shrinkResources:        cfg['shrinkResources'] as bool?,
        lintCheckReleaseBuilds: cfg['lintCheckReleaseBuilds'] as bool?,
        ndkVersion:             cfg['ndkVersion'] as String?,
        ndkDebugSymbolLevel:    cfg['ndkDebugSymbolLevel'] as String?,
        ndkAbiFilters:          ndkRaw is List ? ndkRaw.map((e) => e.toString()).toList() : const [],
      ));
    }));
  }

  static AnnspecFirebase? _parseFirebase(dynamic map) {
    if (map == null) return null;
    final m = map as YamlMap;
    return AnnspecFirebase(
      projectId:      m['project_id'] as String?,
      configFile:     m['config_file'] as String?,
      serviceAccount: m['service_account'] as String?,
    );
  }

  static AnnspecAuth? _parseAuth(dynamic map) {
    if (map == null) return null;
    final m = map as YamlMap;
    return AnnspecAuth(
      clientId: m['clientId'] as String?,
      reversedClientId: m['reversedClientId'] as String?,
    );
  }

  /// Parses a `custom:` YAML map into `Map<groupName, Map<key, value>>`.
  static Map<String, Map<String, dynamic>> _parseCustomMap(dynamic raw) {
    if (raw == null) return const {};
    final outer = raw as YamlMap;
    return Map.fromEntries(outer.entries.map((e) {
      final groupName = e.key as String;
      final groupMap  = e.value as YamlMap;
      final entries   = groupMap.entries.map((ge) {
        final v = ge.value;
        final normalized = v is YamlList ? v.map((i) => i.toString()).toList() : v;
        return MapEntry(ge.key as String, normalized as dynamic);
      });
      return MapEntry(groupName, Map<String, dynamic>.fromEntries(entries));
    }));
  }

  /// Parses `custom:` blocks inside each build_type entry.
  static Map<String, Map<String, Map<String, dynamic>>> _parseCustomPerBuildType(dynamic buildTypesRaw) {
    if (buildTypesRaw == null) return const {};
    final bts = buildTypesRaw as YamlMap;
    final result = <String, Map<String, Map<String, dynamic>>>{};
    for (final e in bts.entries) {
      final bt     = e.key as String;
      final btMap  = e.value as YamlMap?;
      final custom = btMap?['custom'];
      if (custom != null) {
        result[bt] = _parseCustomMap(custom);
      }
    }
    return result;
  }

  /// Deep-merges two custom configs (key-by-key within each group).
  static Map<String, Map<String, dynamic>> _mergeCustom(
    Map<String, Map<String, dynamic>> base,
    Map<String, Map<String, dynamic>> over,
  ) {
    if (over.isEmpty) return base;
    final result = Map<String, Map<String, dynamic>>.from(base);
    for (final e in over.entries) {
      result[e.key] = {...?result[e.key], ...e.value};
    }
    return result;
  }
}
