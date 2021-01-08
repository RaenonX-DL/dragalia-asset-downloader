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
  var tempDir =
      await Directory(config.pathConfig.tempDir).create(recursive: true);

  for (var loc in manifestLocaleFiles.keys) {
    var encrypted = cdn.manifestPath(loc);
    var decrypted = '$encrypted$decryptedExtension';

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
    await exportAssets(
      config,
      decrypted,
      path.join(config.assetStudioConfigDir, 'manifest.json'),
      suffix: loc == manifestMasterLocale ? null : '@$loc',
    );

    await exportAssetsWithManifest(config, loc);
  }

  await tempDir.delete(recursive: true);
}

Future exportAssetsWithManifest(ExportConfig config, String locale) async {
  var isMaster = locale == manifestMasterLocale;
  var manifestFile = File(
    path.join(
      config.pathConfig.exportDir,
      'assets',
      isMaster ? 'manifest.json' : 'manifest@$locale.json',
    ),
  );
  var json = jsonDecode(await manifestFile.readAsString());
  var manifest = Manifest.fromJson(json);

  // Export assets
  if (isMaster) {
    for (var entry in config.single) {
      await exportSingleAsset(config, entry, manifest);
    }

    for (var entry in config.multi) {
      await exportMultiAsset(config, entry, manifest);
    }
  } else {
    await exportMasterAsset(config, locale, manifest);
  }

  await exportAudioAsset(config, manifest);
}

Future exportMasterAsset(
    ExportConfig config, String locale, Manifest manifest) async {
  var masterFile = await manifest.pullUnityAsset('master');

  // ::group:: for GH Actions log grouping
  print('::group::Export master');

  await exportAssets(
    config,
    masterFile.file.path,
    path.join(config.assetStudioConfigDir, 'localized.json'),
    suffix: '@$locale',
  );

  print('::endgroup::');
}

Future exportSingleAsset(
    ExportConfig config, SingleConfig configEntry, Manifest manifest) async {
  var assetName = configEntry.name;
  var assetConfig = configEntry.config;

  print('::group::Export $assetName (single)');

  var singleAsset = await manifest.pullUnityAsset(assetName);

  print('Assets pulled.');

  await exportAssets(
    config,
    singleAsset.file.path,
    path.join(config.assetStudioConfigDir, assetConfig),
  );

  print('Assets exported.');

  print('::endgroup::');
}

Future exportMultiAsset(
    ExportConfig config, MultiConfig configEntry, Manifest manifest) async {
  var assetRegExp = configEntry.regExp;
  var assetConfig = configEntry.config;
  var skipExists = configEntry.skipExists;

  print('::group::Export $assetRegExp (multi)');

  var assets = <ManifestAssetBundle>[];

  for (var pullAction in manifest.pullUnityAssets(assetRegExp)) {
    assets.addAll(await pullAction);
  }

  print('Assets pulled.');

  await exportAssets(
    config,
    await createAssetsFile(config, assets.map((e) => e.file)),
    path.join(config.assetStudioConfigDir, assetConfig),
    skipExists: skipExists,
  );

  print('Assets exported.');

  print('::endgroup::');
}

Future exportAudioAsset(ExportConfig config, Manifest manifest) async {
  print('::group::Export audio');

  var audioAssets = <ManifestAssetBundle>[];

  for (var pullAction
      in manifest.pullRawAssets(config.pathConfig.audio.regExp)) {
    audioAssets.addAll((await pullAction)
        .where((asset) => path.extension(asset.file.path) == '.awb')
        .where((asset) => !config.pathConfig.audio.isIndexHashMatch(asset)));
  }

  print('Assets pulled.');

  if (audioAssets.isEmpty) {
    print('${DateTime.now().toIso8601String()}: No new audio assets detected.');
  }

  for (var idx = 0; idx < audioAssets.length; idx += 1) {
    var audioAsset = audioAssets[idx];

    config.pathConfig.audio.updateIndex(audioAsset);

    print('${DateTime.now().toIso8601String()}: '
        'Exporting Audio (${idx + 1} / ${audioAssets.length}) '
        '${audioAsset.file.path}');
    await exportAudio(config, audioAsset);
  }

  await config.pathConfig.audio.updateIndexFile();

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

Future exportAudioSubsong(ExportConfig config, ManifestAssetBundle awbAsset,
    int subsongIndex, bool streamHasName) async {
  var awbFilePath = awbAsset.file.path;

  if (!await File(awbFilePath).exists()) {
    throw Exception('error: awb audio file not exists. ($awbFilePath)');
  }

  var assetDir = awbAsset.name.split('/');
  var exportDir = Directory(path.joinAll([
    config.pathConfig.exportDir,
    config.pathConfig.audio.exportDir,
    ...assetDir.sublist(0, assetDir.length - 1),
    path.basenameWithoutExtension(awbAsset.name)
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
    awbFilePath,
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
        ' (#$subsongIndex of $awbFilePath to $exportPath)');
  }
}

Future exportAudio(ExportConfig config, ManifestAssetBundle awbAsset) async {
  var awbFile = awbAsset.file;

  if (!await awbFile.exists()) {
    throw Exception('error: awb audio file not exists. (${awbFile.path})');
  }

  // Get metadata
  var arguments = [
    '-I',
    '-m',
    awbFile.path,
  ];
  var proc = await Process.run(
    config.vgmStreamPath,
    arguments,
    runInShell: true,
  );

  var infoJson = jsonDecode(proc.stdout);
  if (!(proc.stderr as String).isNullOrEmpty()) {
    stderr.write(proc.stderr);
  }

  if (await proc.exitCode != 0) {
    throw Exception(
        'error: failed to get the audio metadata. (${awbFile.path})');
  }

  // Export streams
  var streamCount = infoJson['streamInfo']['total'];
  var streamHasName = infoJson['streamInfo']['name'] != null;

  var tasks = Iterable<int>.generate(streamCount, (i) => (i + 1)).map(
      (subsongIndex) async =>
          {exportAudioSubsong(config, awbAsset, subsongIndex, streamHasName)});

  await Future.wait(tasks);
}
