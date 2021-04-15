import 'dart:convert';
import 'dart:io';

import 'package:dl_datamine/config.dart';
import 'package:dl_datamine/dlcdn.dart' as cdn;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'dlcontext.dart';
import 'dlmanifest.dart';

extension Extension on String {
  bool isNullOrEmpty() => this == null || isEmpty;
}

Future exportAllAssets(ExportConfig config) async {
  // Create temporary directory
  var tempDir = await Directory(config.pathConfig.tempDir);
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
  await tempDir.create(recursive: true);

  // Export all assets
  for (var locale in manifestLocaleFiles.keys) {
    // Export a manifest and store it in the temporary directory
    await exportLocalizedManifest(config, locale);
    // Load the exported manifest
    var manifest = await loadLocalizedManifest(config, locale);
    // Try export all listed assets in the manifest
    await exportAssetsWithManifest(config, locale, manifest);
  }

  // Delete temporary directory
  await tempDir.delete(recursive: true);
}

Future exportLocalizedManifest(ExportConfig config, String locale) async {
  var encrypted = cdn.manifestAssetPath(locale);
  var decrypted = '$encrypted$decryptedExtension';

  // Decrypt manifest
  var proc = await Process.start(
    dotnetBin,
    [
      config.decryptDLLPath,
      encrypted,
      decrypted,
      manifestKey,
      manifestIV,
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
  await exportAssets(
    config,
    decrypted,
    path.join(config.assetStudioConfigDir, 'manifest.json'),
    suffix: locale == manifestMasterLocale ? null : '@$locale',
  );
}

Future<Manifest> loadLocalizedManifest(
    ExportConfig config, String locale) async {
  var manifestFile =
      File(cdn.manifestJsonPath(config.pathConfig.exportDir, locale));

  return Manifest.fromJson(jsonDecode(await manifestFile.readAsString()));
}

Future exportAssetsWithManifest(
    ExportConfig config, String locale, Manifest manifest) async {
  var isMaster = locale == manifestMasterLocale;

  // Export assets
  if (isMaster) {
    for (var entry in config.single) {
      await exportSingleAsset(config, locale, entry, manifest);
    }

    for (var entry in config.multi) {
      await exportMultiAsset(config, locale, entry, manifest);
    }
  }

  await exportMasterAsset(config, locale, manifest);

  await exportAudioAsset(config, locale, manifest);
}

Future exportMasterAsset(
    ExportConfig config, String locale, Manifest manifest) async {
  var masterAsset = await manifest.pullUnityAsset('master');

  print('::group::Export master (${locale})');

  if (!config.pathConfig.index.isIndexHashMatch(locale, masterAsset)) {
    await exportAssets(
      config,
      masterAsset.file.path,
      path.join(config.assetStudioConfigDir, 'localized.json'),
      suffix: '@$locale',
    );
    config.pathConfig.index.updateIndex(locale, masterAsset);
    await config.pathConfig.index.updateIndexFile();
  }

  print('::endgroup::');
}

Future exportSingleAsset(ExportConfig config, String locale,
    SingleConfig configEntry, Manifest manifest) async {
  var assetName = configEntry.name;
  var assetConfig = configEntry.config;

  print('::group::Export $assetName (single / ${locale})');

  var singleAsset = await manifest.pullUnityAsset(assetName);

  print('Assets pulled.');

  if (!config.pathConfig.index.isIndexHashMatch(locale, singleAsset)) {
    await exportAssets(
      config,
      singleAsset.file.path,
      path.join(config.assetStudioConfigDir, assetConfig),
    );
    config.pathConfig.index.updateIndex(locale, singleAsset);
    await config.pathConfig.index.updateIndexFile();
  }

  print('Assets exported.');

  print('::endgroup::');
}

Future exportMultiAsset(ExportConfig config, String locale,
    MultiConfig configEntry, Manifest manifest) async {
  var assetRegExp = configEntry.regExp;
  var assetConfig = configEntry.config;
  var skipExists = configEntry.skipExists;

  print('::group::Export $assetRegExp (multi / ${locale})');

  var assets = <ManifestAssetBundle>[];

  for (var pullAction in manifest.pullUnityAssets(assetRegExp,
      filter: (asset) =>
          !config.pathConfig.index.isIndexHashMatch(locale, asset))) {
    assets.addAll(await pullAction);
  }

  print('Assets pulled.');

  var assetFiles = assets.map((e) => e.file);
  if (assetFiles.isNotEmpty) {
    await exportAssets(
      config,
      await createAssetsFile(config, assets.map((e) => e.file)),
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

Future<List<ManifestAssetBundle>> pullAudioAssets(
    ExportConfig config, String locale, Manifest manifest) async {
  var assets = <ManifestAssetBundle>[];

  for (var pullAction in manifest.pullRawAssets(config.pathConfig.audio.regExp,
      filter: (asset) =>
          !config.pathConfig.index.isIndexHashMatch(locale, asset))) {
    assets.addAll((await pullAction).where((asset) =>
        <String>['.awb', '.acb'].contains(path.extension(asset.file.path))));
  }

  return assets;
}

Future<List<ManifestAssetBundle>> getAudioAssetsForExport(
    List<ManifestAssetBundle> assets) async {
  var isSameAudioAsset =
      (ManifestAssetBundle acbAsset, ManifestAssetBundle awbAsset) =>
          path.basenameWithoutExtension(acbAsset.file.path) ==
          path.basenameWithoutExtension(awbAsset.file.path);

  var awbAssets = <ManifestAssetBundle>[];
  var acbAssets = <ManifestAssetBundle>[];
  var ret = <ManifestAssetBundle>[];

  awbAssets.addAll(assets
      .where((asset) => path.extension(asset.file.path).endsWith('.awb')));
  acbAssets.addAll(assets
      .where((asset) => path.extension(asset.file.path).endsWith('.acb')));

  ret.addAll(awbAssets);
  ret.addAll(acbAssets.where((acbAsset) =>
      !awbAssets.any((awbAsset) => isSameAudioAsset(acbAsset, awbAsset))));

  return ret;
}

Future exportAudioAsset(
    ExportConfig config, String locale, Manifest manifest) async {
  print('::group::Export audio (${locale})');

  var audioAssets = await pullAudioAssets(config, locale, manifest);
  var audioAssetsForExport = await getAudioAssetsForExport(audioAssets);

  print('Assets pulled.');

  if (audioAssetsForExport.isEmpty) {
    print(
        '${DateTime.now().toIso8601String()}: No new audio assets to be exported.');
    print('::endgroup::');
    return;
  }

  // Export audio
  for (var idx = 0; idx < audioAssetsForExport.length; idx += 1) {
    var audioAsset = audioAssetsForExport[idx];

    print('${DateTime.now().toIso8601String()}: '
        'Exporting Audio (${idx + 1} / ${audioAssetsForExport.length}) '
        '${audioAsset.file.path}');
    await exportAudio(config, audioAsset);
  }

  // Update index
  for (var idx = 0; idx < audioAssets.length; idx += 1) {
    config.pathConfig.index.updateIndex(locale, audioAssets[idx]);
  }

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

Future exportAssets(
  ExportConfig config,
  String bundlePath,
  String settingPath, {
  String suffix,
  bool skipExists = false,
}) async {
  var arguments = [
    'convert',
    bundlePath,
    config.pathConfig.exportDir,
    '-m',
    settingPath,
  ];
  if (suffix != null && suffix.isNotEmpty) {
    arguments.addAll(['--with-suffix', suffix]);
  }
  if (skipExists) {
    arguments.add('--skip-exists');
  }
  var proc = await Process.start(
    config.assetStudioCLIPath,
    arguments,
    runInShell: true,
  );

  await stdout.addStream(proc.stdout);
  await stderr.addStream(proc.stderr);

  if (await proc.exitCode != 0) {
    throw Exception('error: failed to export assets. ($bundlePath)');
  }
}

Future exportAudioSubsong(ExportConfig config, ManifestAssetBundle asset,
    int subsongIndex, bool streamHasName) async {
  var assetPath = asset.file.path;

  if (!await File(assetPath).exists()) {
    throw Exception('error: awb audio file not exists. ($assetPath)');
  }

  var assetDir = asset.name.split('/');
  var exportDir = Directory(path.joinAll([
    config.pathConfig.exportDir,
    config.pathConfig.audio.exportDir,
    ...assetDir.sublist(0, assetDir.length - 1),
    path.basenameWithoutExtension(asset.name)
  ]));
  await exportDir.create(recursive: true);

  var exportPath =
      path.join(exportDir.path, streamHasName ? '?n.wav' : '?03s.wav');

  if (await File(exportPath).exists()) {
    return;
  }

  var arguments = [
    '-s',
    subsongIndex.toString(),
    '-i',
    '-o',
    exportPath,
    assetPath,
  ];
  var proc = await Process.run(
    config.vgmStreamPath,
    arguments,
    runInShell: true,
  );

  if (!(proc.stderr as String).isNullOrEmpty()) {
    stderr.write(proc.stderr);
  }

  if (await proc.exitCode != 0) {
    throw Exception('error: failed to export the audio subsong.'
        ' (#$subsongIndex of $assetPath to $exportPath)');
  }
}

Future exportAudio(ExportConfig config, ManifestAssetBundle audioAsset) async {
  var audioFile = audioAsset.file;

  if (!await audioFile.exists()) {
    throw Exception('error: audio file not exists. (${audioFile.path})');
  }

  // Get metadata
  var arguments = [
    '-I',
    '-m',
    audioFile.path,
  ];
  var proc = await Process.run(
    config.vgmStreamPath,
    arguments,
    runInShell: true,
  );

  var stdErr = proc.stderr as String;
  if (!(stdErr).isNullOrEmpty()) {
    stderr.write(stdErr + '\n');
  }

  if (await proc.exitCode != 0) {
    throw Exception(
        'error: failed to get the audio metadata. (${audioFile.path})');
  }

  var infoJson = jsonDecode(proc.stdout);

  // Export streams
  var streamCount = infoJson['streamInfo']['total'];
  var streamHasName = infoJson['streamInfo']['name'] != null;

  var tasks = Iterable<int>.generate(streamCount, (i) => (i + 1)).map(
      (subsongIndex) async => {
            exportAudioSubsong(config, audioAsset, subsongIndex, streamHasName)
          });

  await Future.wait(tasks);
}
