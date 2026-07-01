class AnnspecBuildTypeConfig {
  final String? idSuffix;
  final String? nameSuffix;
  final String? gmsAdsId;
  final bool? minifyEnabled;
  final bool? shrinkResources;
  final bool? lintCheckReleaseBuilds;
  final String? ndkVersion;
  final String? ndkDebugSymbolLevel;
  final List<String> ndkAbiFilters;

  AnnspecBuildTypeConfig({
    this.idSuffix,
    this.nameSuffix,
    this.gmsAdsId,
    this.minifyEnabled,
    this.shrinkResources,
    this.lintCheckReleaseBuilds,
    this.ndkVersion,
    this.ndkDebugSymbolLevel,
    this.ndkAbiFilters = const [],
  });
}

class AnnspecAuth {
  final String? clientId;
  final String? reversedClientId;
  AnnspecAuth({this.clientId, this.reversedClientId});
}

class AnnspecFirebase {
  final String? projectId;
  final String? configFile;
  final String? serviceAccount;
  AnnspecFirebase({this.projectId, this.configFile, this.serviceAccount});
}

class AnnspecFlavor {
  final String key;
  final String? id;
  final String? idSuffix;
  final String? name;
  final String? mainFile;
  final String? versionName;
  final String? versionCode;
  final String? gmsAdsId; // resolved: buildType.admob.gms_ads_id ?? flavor.admob.gms_ads_id ?? default.admob.gms_ads_id
  final AnnspecFirebase? firebaseRelease;
  final AnnspecFirebase? firebaseDebug;
  final AnnspecAuth? authRelease;
  final AnnspecAuth? authDebug;
  // store fields
  final String? googlePlayPriority;
  final String? samsungAppId;
  final String? amazonAppId;
  final String? appleId;

  // per-build-type id/name suffix
  final Map<String, AnnspecBuildTypeConfig> buildTypes;

  /// Resolved custom config per build type — key: buildType, value: group → key → value.
  final Map<String, Map<String, Map<String, dynamic>>> customByBuildType;

  AnnspecFlavor({
    required this.key,
    this.id,
    this.idSuffix,
    this.name,
    this.mainFile,
    this.versionName,
    this.versionCode,
    this.gmsAdsId,
    this.firebaseRelease,
    this.firebaseDebug,
    this.authRelease,
    this.authDebug,
    this.googlePlayPriority,
    this.samsungAppId,
    this.amazonAppId,
    this.appleId,
    this.buildTypes = const {},
    this.customByBuildType = const {},
  });

  String effectiveId(String baseId, String buildType) {
    final suffix = buildTypes[buildType]?.idSuffix ?? '';
    return baseId + (idSuffix ?? '') + suffix;
  }

  String effectiveName(String baseName, String buildType) {
    final suffix = buildTypes[buildType]?.nameSuffix ?? '';
    return (name ?? baseName) + suffix;
  }
}

class AnnspecPlatform {
  final String key; // android | ios | web | windows
  final String? baseId;
  final String? baseName;
  final String? defaultVersionName;
  final String? defaultVersionCode;
  final String? defaultGmsAdsId;
  final String? teamId;
  final AnnspecFirebase? defaultFirebaseRelease;
  final AnnspecFirebase? defaultFirebaseDebug;
  final AnnspecAuth? defaultAuthRelease;
  final AnnspecAuth? defaultAuthDebug;
  final List<AnnspecFlavor> flavors;
  // android-specific
  final int? minSdk;
  final String? signingKeyFile;
  final String? gradlePluginId;
  final String? gradlePluginVersion;
  // credentials
  final String? googlePlayApiKey;
  final String? appStoreApiKey;
  final String? appStoreExportPlist;

  // default build type configs
  final Map<String, AnnspecBuildTypeConfig> defaultBuildTypes;

  AnnspecPlatform({
    required this.key,
    this.baseId,
    this.baseName,
    this.defaultVersionName,
    this.defaultVersionCode,
    this.defaultGmsAdsId,
    this.teamId,
    this.defaultFirebaseRelease,
    this.defaultFirebaseDebug,
    this.defaultAuthRelease,
    this.defaultAuthDebug,
    this.flavors = const [],
    this.minSdk,
    this.signingKeyFile,
    this.gradlePluginId,
    this.gradlePluginVersion,
    this.googlePlayApiKey,
    this.appStoreApiKey,
    this.appStoreExportPlist,
    this.defaultBuildTypes = const {},
  });
}

class AnnspecModel {
  final List<AnnspecPlatform> platforms;
  final AnnspecIntegrations? integrations;

  AnnspecModel({required this.platforms, this.integrations});

  AnnspecPlatform? platform(String key) =>
      platforms.where((p) => p.key == key).firstOrNull;
}

class AnnspecIntegrations {
  final bool fastlane;
  final bool melos;
  final bool firebase;
  AnnspecIntegrations({this.fastlane = false, this.melos = false, this.firebase = false});
}
