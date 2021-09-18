import 'dart:convert';
import 'dart:io';

import 'package:dl_datamine/config.dart';
import 'package:path/path.dart' as path;

import 'dlcdn.dart';
import 'dlmanifest.dart';

extension Extension on String? {
  bool isNullOrEmpty() => this == null || this!.isEmpty;
}

Future<List<ManifestAssetBundle>> pullAudioAssets(CdnInfo cdnInfo,
    ExportConfig config, String locale, Manifest manifest) async {
  var assets = <ManifestAssetBundle>[];

  for (var pullAction in manifest.pullRawAssets(
      cdnInfo, config.pathConfig.audio.regExp,
      filter: (asset) =>
          !config.pathConfig.index.isIndexHashMatch(locale, asset))) {
    assets.addAll((await pullAction).where((asset) =>
        <String>['.awb', '.acb'].contains(path.extension(asset.file!.path))));
  }

  return assets;
}

Future<List<ManifestAssetBundle>> getAudioAssetsForExport(
    List<ManifestAssetBundle> assets) async {
  var isSameAudioAsset =
      (ManifestAssetBundle acbAsset, ManifestAssetBundle awbAsset) =>
          path.basenameWithoutExtension(acbAsset.file!.path) ==
          path.basenameWithoutExtension(awbAsset.file!.path);

  var awbAssets = <ManifestAssetBundle>[];
  var acbAssets = <ManifestAssetBundle>[];
  var ret = <ManifestAssetBundle>[];

  awbAssets.addAll(assets
      .where((asset) => path.extension(asset.file!.path).endsWith('.awb')));
  acbAssets.addAll(assets
      .where((asset) => path.extension(asset.file!.path).endsWith('.acb')));

  ret.addAll(awbAssets);
  ret.addAll(acbAssets.where((acbAsset) =>
      !awbAssets.any((awbAsset) => isSameAudioAsset(acbAsset, awbAsset))));

  return ret;
}

Future exportAudioAsset(CdnInfo cdnInfo, ExportConfig config, String locale,
    Manifest manifest) async {
  print('::group::Export audio ($locale)');

  var audioAssets = await pullAudioAssets(cdnInfo, config, locale, manifest);
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
        '${audioAsset.file!.path}');
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

Future exportAssets(
  ExportConfig config,
  String locale,
  String bundlePath,
  String settingPath, {
  String? suffix,
  bool skipExists = false,
}) async {
  var arguments = [
    'convert',
    bundlePath,
    config.pathConfig.getExportDir(locale: locale),
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
  var assetPath = asset.file!.path;

  if (!await File(assetPath).exists()) {
    throw Exception('error: awb audio file not exists. ($assetPath)');
  }

  var assetDir = asset.name.split('/');
  var exportDir = Directory(path.joinAll([
    config.pathConfig.getExportDir(),
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

  if (proc.exitCode != 0) {
    throw Exception('error: failed to export the audio subsong.'
        ' (#$subsongIndex of $assetPath to $exportPath)');
  }
}

Future exportAudio(ExportConfig config, ManifestAssetBundle audioAsset) async {
  var audioFile = audioAsset.file;

  if (!await audioFile!.exists()) {
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

  if (proc.exitCode != 0) {
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
