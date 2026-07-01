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
  /// Shared service_account for this flavor, applies to all build types that
  /// don't set their own. Set via  flavor.<n>.firebase.service_account.
  final String? flavorServiceAccount;
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
    this.flavorServiceAccount,
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
  /// Shared service_account for all flavors and build types that don't set
  /// their own. Set via  default.firebase.service_account.
  final String? defaultServiceAccount;
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
    this.defaultServiceAccount,
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

  /// Resolves service_account for a given platform / flavor / build type using
  /// a 4-level cascade (most-specific wins):
  ///   1. flavor.build_types.<bt>.firebase.service_account
  ///   2. flavor.firebase.service_account
  ///   3. default.build_types.<bt>.firebase.service_account
  ///   4. default.firebase.service_account
  static String? resolveServiceAccount(
    AnnspecPlatform platform,
    AnnspecFlavor? flavor,
    String buildType,
  ) {
    final fb = buildType == 'release'
        ? (flavor?.firebaseRelease ?? platform.defaultFirebaseRelease)
        : (flavor?.firebaseDebug   ?? platform.defaultFirebaseDebug);

    final defaultFb = buildType == 'release'
        ? platform.defaultFirebaseRelease
        : platform.defaultFirebaseDebug;

    return fb?.serviceAccount              // level 1 or 3 (build-type specific)
        ?? flavor?.flavorServiceAccount    // level 2
        ?? defaultFb?.serviceAccount       // level 3 when flavor has no bt firebase
        ?? platform.defaultServiceAccount; // level 4
  }
}

class AnnspecIntegrations {
  final bool fastlane;
  final bool melos;
  final bool firebase;
  AnnspecIntegrations({this.fastlane = false, this.melos = false, this.firebase = false});
}
