import 'dart:convert';
import 'dart:io';

import 'package:dl_datamine/config.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'dlaudio.dart';
import 'dlcdn.dart';
import 'dlcontext.dart';
import 'dlmanifest.dart';

Future exportAllAssets(CdnInfo cdnInfo, ExportConfig config) async {
  // Create temporary directory
  var tempDir = Directory(config.pathConfig.tempDir);
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
  await tempDir.create(recursive: true);

  // Export all assets
  for (var locale in manifestLocaleFiles.keys) {
    // Export a manifest and store it in the temporary directory
    await exportLocalizedManifest(cdnInfo, config, locale);
    // Load the exported manifest
    var manifest = await loadLocalizedManifest(config, locale);
    // Try export all listed assets in the manifest
    await exportAssetsWithManifest(cdnInfo, config, locale, manifest);
  }

  // Delete temporary directory
  await tempDir.delete(recursive: true);
}

Future exportLocalizedManifest(
    CdnInfo cdnInfo, ExportConfig config, String locale) async {
  var encrypted = cdnInfo.manifestAssetPath(locale);
  var decrypted = '$encrypted$decryptedExtension';

  // Decrypt manifest
  var proc = await Process.start(
    dotnetBin,
    [
      config.decryptDLLPath,
      encrypted,
      decrypted,
      config.manifestKey,
      config.manifestIV,
    ],
    runInShell: true,
  );
  await stdout.addStream(proc.stdout);
  await stderr.addStream(proc.stderr);

  var exitCode = await proc.exitCode;

  if (exitCode != 0) {
    throw Exception('error: failed to decrypt $encrypted ($exitCode)');
  }

  // Export manifest file
  await exportAssets(config, locale, decrypted,
      path.join(config.assetStudioConfigDir, 'manifest.json'));
}

Future<Manifest> loadLocalizedManifest(
    ExportConfig config, String locale) async {
  var manifestFile = File(
      manifestJsonPath(config.pathConfig.getExportDir(locale: locale), locale));

  return Manifest.fromJson(jsonDecode(await manifestFile.readAsString()));
}

Future exportAssetsWithManifest(CdnInfo cdnInfo, ExportConfig config,
    String locale, Manifest manifest) async {
  var isMasterLocale = locale == manifestMasterLocale;

  // Export assets
  for (var entry in config.single) {
    if (entry.multiLocale || isMasterLocale) {
      await exportSingleAsset(cdnInfo, config, locale, entry, manifest);
    }
  }

  for (var entry in config.multi) {
    if (entry.multiLocale || isMasterLocale) {
      await exportMultiAsset(cdnInfo, config, locale, entry, manifest);
    }
  }

  await exportMasterAsset(cdnInfo, config, locale, manifest);

  await exportAudioAsset(cdnInfo, config, locale, manifest);
}

Future exportMasterAsset(CdnInfo cdnInfo, ExportConfig config, String locale,
    Manifest manifest) async {
  var masterAsset = await manifest.pullUnityAsset(cdnInfo, 'master');

  print('::group::Export master ($locale)');

  if (!config.pathConfig.index.isIndexHashMatch(locale, masterAsset)) {
    await exportAssets(
      config,
      locale,
      masterAsset.file!.path,
      path.join(config.assetStudioConfigDir, 'localized.json'),
      suffix: '@$locale',
    );
    config.pathConfig.index.updateIndex(locale, masterAsset);
    await config.pathConfig.index.updateIndexFile();
  }

  print('::endgroup::');
}

Future exportSingleAsset(CdnInfo cdnInfo, ExportConfig config, String locale,
    SingleConfig configEntry, Manifest manifest) async {
  var assetName = configEntry.name;
  var assetConfig = configEntry.config;

  print('::group::Export $assetName (single / $locale)');

  var singleAsset = await manifest.pullUnityAsset(cdnInfo, assetName);

  print('Assets pulled.');

  if (!config.pathConfig.index.isIndexHashMatch(locale, singleAsset)) {
    await exportAssets(
      config,
      locale,
      singleAsset.file!.path,
      path.join(config.assetStudioConfigDir, assetConfig),
    );
    config.pathConfig.index.updateIndex(locale, singleAsset);
    await config.pathConfig.index.updateIndexFile();
  }

  print('Assets exported.');

  print('::endgroup::');
}

Future exportMultiAsset(CdnInfo cdnInfo, ExportConfig config, String locale,
    MultiConfig configEntry, Manifest manifest) async {
  var assetRegExp = configEntry.regExp;
  var assetConfig = configEntry.config;
  var skipExists = configEntry.skipExists;

  print('::group::Export $assetRegExp (multi / $locale)');

  var assets = <ManifestAssetBundle>[];

  for (var pullAction in manifest.pullUnityAssets(cdnInfo, assetRegExp,
      filter: (asset) =>
          !config.pathConfig.index.isIndexHashMatch(locale, asset))) {
    assets.addAll(await pullAction);
  }

  print('Assets pulled.');

  var assetFiles = assets.map((e) => e.file);
  if (assetFiles.isNotEmpty) {
    await exportAssets(
      config,
      locale,
      await createAssetsFile(config, assets.map((e) => e.file!)),
      path.join(config.assetStudioConfigDir, assetConfig),
      skipExists: skipExists,
    );
  }

  assets.forEach((asset) {
    config.pathConfig.index.updateIndex(locale, asset);
  });
  await config.pathConfig.index.updateIndexFile();

  print('Assets exported.');

  print('::endgroup::');
}

Future<String> createAssetsFile(
    ExportConfig config, Iterable<File> assetFiles) async {
  var file = File(path.join(config.pathConfig.tempDir, Uuid().v1() + '.files'));
  var writer = file.openWrite();
  for (var assetFile in assetFiles) {
    writer.writeln(assetFile.path);
  }
  await writer.close();
  return file.path;
}
