import 'dart:convert';
import 'dart:io';
import 'package:dl_datamine/dlcdn.dart' as cdn;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'dlmanifest.dart';
import 'dlcontext.dart';

Future exportAllAssets() async {
  var tempDir = await Directory(tempOutputPath).create(recursive: true);

  for (var loc in manifestLocaleFiles.keys) {
    var encrypted = cdn.manifestPath(loc);
    var decrypted = '$encrypted$decryptedExtension';

    var proc = await Process.start(
      dotnetBin,
      [
        current.decryptBin,
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
      decrypted,
      path.join(current.assetStudioSettingPath, 'manifest.json'),
      suffix: loc == manifestMasterLocale ? null : '@$loc',
    );

    await exportAssetsWithManifest(loc);
  }

  await tempDir.delete(recursive: true);
}

Future exportAssetsWithManifest(String locale) async {
  var isMaster = locale == manifestMasterLocale;
  var manifestFile = File(
    path.join(
      exportOutputDir,
      'assets',
      isMaster ? 'manifest.json' : 'manifest@$locale.json',
    ),
  );
  var json = jsonDecode(await manifestFile.readAsString());
  var manifest = Manifest.fromJson(json);

  var configJson = jsonDecode(
      await File(configPath).readAsString()
  );

  if (isMaster) {
    // Get single asset parsing config
    for (var entry in configJson['single']) {
      var assetName = entry['name'];
      var assetConfig = entry['config'];

      // ::group:: for GH Actions log grouping
      print('::group::Export $assetName (single)');

      var singleAsset = await manifest.pullAsset(assetName);
      await exportAssets(
        singleAsset.path,
        path.join(current.assetStudioSettingPath, assetConfig),
      );

      print('::endgroup::');
    }

    // Get multi asset parsing config
    for (var entry in configJson['multi']) {
      var assetRegExp = entry['regExp'];
      var assetConfig = entry['config'];
      var skipExists = entry['skipExists'];

      // ::group:: for GH Actions log grouping
      print('::group::Export $assetRegExp (multi)');

      var multiAsset = await manifest.pullAssets(RegExp(assetRegExp));
      await exportAssets(
        await createAssetsFile(multiAsset),
        path.join(current.assetStudioSettingPath, assetConfig),
        skipExists: skipExists,
      );

      print('::endgroup::');
    }
  } else {
    var masterFile = await manifest.pullAsset('master');

    // ::group:: for GH Actions log grouping
    print('::group::Export master');

    await exportAssets(
      masterFile.path,
      path.join(current.assetStudioSettingPath, 'localized.json'),
      suffix: '@$locale',
    );

    print('::endgroup::');
  }
}

Future<String> createAssetsFile(List<File> assetFiles) async {
  var file = File(path.join(tempOutputPath, Uuid().v1() + '.files'));
  var writer = file.openWrite();
  for (var assetFile in assetFiles) {
    writer.writeln(assetFile.path);
  }
  await writer.close();
  return file.path;
}

Future exportAssets(
  String bundlePath,
  String settingPath, {
  String suffix,
  bool skipExists = false,
}) async {
  var arguments = [
    'convert',
    bundlePath,
    exportOutputDir,
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
    current.assetStudioBin,
    arguments,
    runInShell: true,
  );

  await stdout.addStream(proc.stdout);
  await stderr.addStream(proc.stderr);

  if (await proc.exitCode != 0) {
    throw Exception('error: export assets on failure. ($bundlePath)');
  }
}
