import 'dart:convert';
import 'dart:io';

import 'package:dl_datamine/dlmanifest.dart';
import 'package:path/path.dart' as path;

class SingleConfig {
  final String name;
  final String config;

  SingleConfig._(this.name, this.config);

  static List<SingleConfig> parse(List<dynamic> configEntries) {
    return configEntries
        .map((config) => SingleConfig._(config['name'], config['config']))
        .toList();
  }
}

class MultiConfig {
  final RegExp regExp;
  final String config;
  final bool skipExists;

  MultiConfig._(this.regExp, this.config, this.skipExists);

  static List<MultiConfig> parse(List<dynamic> configEntries) {
    return configEntries
        .map((config) => MultiConfig._(
            RegExp(config['regExp']), config['config'], config['skipExists']))
        .toList();
  }
}

class AudioConfig {
  final RegExp regExp;
  final String exportDir;
  final File indexFile;
  final Map<String, dynamic> index;
  final String vgmStreamDir;
  final String vgmStreamExe;

  AudioConfig._(this.regExp, this.exportDir, this.indexFile, this.index,
      this.vgmStreamDir, this.vgmStreamExe);

  static Future<AudioConfig> parse(
      String incrPath, Map<String, dynamic> configBody) async {
    var indexFile = await File(path.join(incrPath, configBody['indexPath']));
    // Create initial index file if not exists
    if (!await indexFile.parent.exists()) {
      await indexFile.parent.create(recursive: true);
    }
    if (!await indexFile.exists()) {
      await indexFile.writeAsString(jsonEncode({}));
    }

    return AudioConfig._(
        RegExp(configBody['regExp']),
        path.joinAll(configBody['exportDir'].split('/')),
        indexFile,
        jsonDecode(await indexFile.readAsString()),
        path.joinAll(configBody['vgmStreamDir'].split('/')),
        configBody['vgmStreamExe']);
  }

  Future updateIndexFile() async {
    await indexFile.writeAsString(jsonEncode(index));
  }

  void updateIndex(ManifestAssetBundle asset) {
    index[asset.name] = asset.hash;
  }

  bool isIndexHashMatch(ManifestAssetBundle asset) {
    return index.containsKey(asset.name) && index[asset.name] == asset.hash;
  }
}

class DecrypterConfig {
  final String dir;
  final String dll;

  DecrypterConfig._(this.dir, this.dll);

  factory DecrypterConfig.parse(Map<String, dynamic> configBody) {
    return DecrypterConfig._(
        path.joinAll(configBody['dir'].split('/')), configBody['dll']);
  }
}

class AssetStudioConfig {
  final String configDir;
  final String cliDir;
  final String cliExe;

  AssetStudioConfig._(this.configDir, this.cliDir, this.cliExe);

  factory AssetStudioConfig.parse(Map<String, dynamic> configBody) {
    return AssetStudioConfig._(path.joinAll(configBody['configDir'].split('/')),
        path.joinAll(configBody['cliDir'].split('/')), configBody['cliExe']);
  }
}

class PathConfig {
  final DecrypterConfig decrypter;
  final AssetStudioConfig assetStudio;
  final AudioConfig audio;
  final String cdnDir;
  final String exportDir;
  final String incrDir;
  final String tempDir;

  PathConfig._(this.decrypter, this.assetStudio, this.audio, this.cdnDir,
      this.exportDir, this.incrDir, this.tempDir);

  static Future<PathConfig> parse(Map<String, dynamic> configBody) async {
    var cdnDir = path.joinAll(configBody['cdnDir'].split('/'));
    var exportDir = path.joinAll(configBody['exportDir'].split('/'));
    var incrDir = path.joinAll(configBody['incrDir'].split('/'));
    var tempDir = path.joinAll(configBody['tempDir'].split('/'));

    return PathConfig._(
        DecrypterConfig.parse(configBody['decrypter']),
        AssetStudioConfig.parse(configBody['assetStudio']),
        await AudioConfig.parse(incrDir, configBody['audio']),
        cdnDir,
        exportDir,
        incrDir,
        tempDir);
  }
}

class ExportConfig {
  final String root;
  final List<SingleConfig> single;
  final List<MultiConfig> multi;
  final PathConfig pathConfig;

  ExportConfig._(this.root, this.single, this.multi, this.pathConfig);

  /// Public factory
  static Future<ExportConfig> create(String root, String configPath) async {
    var configBody = jsonDecode(await File(configPath).readAsString());

    var single = SingleConfig.parse(configBody['single']);
    var multi = MultiConfig.parse(configBody['multi']);

    var path = await PathConfig.parse(configBody['paths']);

    return ExportConfig._(root, single, multi, path);
  }

  String get decryptDLLPath {
    return path.join(root, pathConfig.decrypter.dir, pathConfig.decrypter.dll);
  }

  String get assetStudioCLIPath {
    return path.join(
        root, pathConfig.assetStudio.cliDir, pathConfig.assetStudio.cliExe);
  }

  String get assetStudioConfigDir {
    return path.join(root, pathConfig.assetStudio.configDir);
  }

  String get vgmStreamPath {
    return path.join(
        root, pathConfig.audio.vgmStreamDir, pathConfig.audio.vgmStreamExe);
  }
}
