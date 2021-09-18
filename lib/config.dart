import 'dart:convert';
import 'dart:io';

import 'package:dl_datamine/dlcontext.dart';
import 'package:dl_datamine/dlmanifest.dart';
import 'package:path/path.dart' as path;

class SingleConfig {
  final String name;
  final String config;
  final bool multiLocale;

  SingleConfig._(this.name, this.config, this.multiLocale);

  static List<SingleConfig> parse(List<dynamic> configEntries) {
    return configEntries
        .map((config) => SingleConfig._(
            config['name'], config['config'], config['multiLocale']))
        .toList();
  }
}

class MultiConfig {
  final RegExp regExp;
  final String config;
  final bool skipExists;
  final bool multiLocale;
  final String? partsImageRegex;

  MultiConfig._(this.regExp, this.config, this.skipExists, this.multiLocale,
      this.partsImageRegex);

  static List<MultiConfig> parse(List<dynamic> configEntries) {
    return configEntries
        .map((config) => MultiConfig._(
            RegExp(config['regExp']),
            config['config'],
            config['skipExists'],
            config['multiLocale'],
            config['partsImageRegex']))
        .toList();
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

class AudioConfig {
  final RegExp regExp;
  final String exportDir;
  final String vgmStreamDir;
  final String vgmStreamExe;

  AudioConfig._(
      this.regExp, this.exportDir, this.vgmStreamDir, this.vgmStreamExe);

  factory AudioConfig.parse(Map<String, dynamic> configBody) {
    return AudioConfig._(
        RegExp(configBody['regExp']),
        path.joinAll(configBody['exportDir'].split('/')),
        path.joinAll(configBody['vgmStreamDir'].split('/')),
        configBody['vgmStreamExe']);
  }
}

class IndexConfig {
  final File indexFile;
  final Map<String, dynamic> index;

  IndexConfig._(
    this.indexFile,
    this.index,
  );

  static Future<IndexConfig> parse(
      String incrDir, Map<String, dynamic> configBody) async {
    var indexFile = File(path.join(incrDir, configBody['indexPath']));
    // Create initial index file if not exists
    if (!await indexFile.parent.exists()) {
      await indexFile.parent.create(recursive: true);
    }
    if (!await indexFile.exists()) {
      await indexFile.writeAsString(jsonEncode({}));
    }

    return IndexConfig._(indexFile, jsonDecode(await indexFile.readAsString()));
  }

  Future updateIndexFile() async {
    await indexFile.writeAsString(jsonEncode(index));
  }

  void updateIndex(String locale, ManifestAssetBundle asset) {
    if (!index.containsKey(locale)) {
      index[locale] = {};
    }

    index[locale][asset.name] = asset.hash;
  }

  bool isIndexHashMatch(String locale, ManifestAssetBundle asset) {
    if (!index.containsKey(locale)) {
      return false;
    }

    if (!index[locale].containsKey(asset.name)) {
      return false;
    }

    return index[locale][asset.name] == asset.hash;
  }
}

class PathConfig {
  final DecrypterConfig decrypter;
  final AssetStudioConfig assetStudio;
  final AudioConfig audio;
  final IndexConfig index;
  final String cdnDir;
  final String _exportDir;
  final String incrDir;
  final String tempDir;

  PathConfig._(this.decrypter, this.assetStudio, this.audio, this.index,
      this.cdnDir, this._exportDir, this.incrDir, this.tempDir);

  String getExportDir({String locale = manifestMasterLocale}) {
    return locale == manifestMasterLocale
        ? _exportDir
        : '$_exportDir/localized/$locale';
  }

  static Future<PathConfig> parse(Map<String, dynamic> configBody) async {
    var incrDir = path.joinAll(configBody['incrDir'].split('/'));

    return PathConfig._(
        DecrypterConfig.parse(configBody['decrypter']),
        AssetStudioConfig.parse(configBody['assetStudio']),
        AudioConfig.parse(configBody['audio']),
        await IndexConfig.parse(incrDir, configBody['index']),
        path.joinAll(configBody['cdnDir'].split('/')),
        path.joinAll(configBody['exportDir'].split('/')),
        incrDir,
        path.joinAll(configBody['tempDir'].split('/')));
  }
}

class ExportConfig {
  final String root;
  final List<SingleConfig> single;
  final List<MultiConfig> multi;
  final PathConfig pathConfig;
  final String manifestKey;
  final String manifestIV;

  ExportConfig._(this.root, this.single, this.multi, this.pathConfig,
      this.manifestKey, this.manifestIV);

  /// Public factory
  static Future<ExportConfig> create(String root, String configPath,
      String manifestKey, String manifestIV) async {
    var configBody = jsonDecode(await File(configPath).readAsString());

    var single = SingleConfig.parse(configBody['single']);
    var multi = MultiConfig.parse(configBody['multi']);

    var path = await PathConfig.parse(configBody['paths']);

    return ExportConfig._(root, single, multi, path, manifestKey, manifestIV);
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
