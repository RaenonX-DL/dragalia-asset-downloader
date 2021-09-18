import 'dart:io' as io;
import 'dart:io';

import 'package:dl_datamine/config.dart';
import 'package:path/path.dart' as path;

const bool kReleaseMode =
    bool.fromEnvironment('dart.vm.product', defaultValue: false);

const dotnetBin = 'dotnet';
const decryptedExtension = '.decrypted';
Uri cdnBaseUrl = Uri.https('dragalialost.akamaized.net', '/dl');

var versionCode = 'ziG2a3wZmqghCYnc';

const manifestMasterLocale = 'jp';
const manifestLocaleFiles = {
  manifestMasterLocale: 'assetbundle.manifest',
  'en': 'assetbundle.en_us.manifest',
  'cn': 'assetbundle.zh_cn.manifest',
  'tw': 'assetbundle.zh_tw.manifest',
};

var contextRoot =
    kReleaseMode ? path.dirname(io.Platform.resolvedExecutable) : '.';

String? getArgumentsOptionValue(List<String> arguments, String flag) {
  var i = arguments.indexOf(flag);
  if (i >= 0 && i + 1 < arguments.length) {
    return arguments[i + 1];
  }
  return null;
}

Future<ExportConfig> initWithArguments(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('usage: dldump <VersionCode> '
        '[--config-path <path>]'
        '[--iv <iv>] '
        '[--key <key>] ');
    io.exit(1);
  }

  var manifestIV = getArgumentsOptionValue(arguments, '--iv');
  if (manifestIV == null) {
    print('IV is required for decrypting the manifest');
    io.exit(1);
  }

  var manifestKey = getArgumentsOptionValue(arguments, '--key');
  if (manifestKey == null) {
    print('Key is required for decrypting the manifest');
    io.exit(1);
  }

  versionCode = arguments[0];

  var configPath = getArgumentsOptionValue(arguments, '--config-path');
  if (configPath == null) {
    print('Config path not specified');
    io.exit(1);
  }
  configPath = path.normalize(configPath);
  if (!await File(configPath).exists()) {
    print('config file not exists');
    io.exit(1);
  }

  return await ExportConfig.create(
      contextRoot, configPath, manifestIV, manifestKey);
}

Future<File?> _incrementalRecordFile(
    ExportConfig config, File f, bool autoCreateDirectory) async {
  if (path.isWithin(config.pathConfig.getExportDir(), f.path)) {
    var rel = path.relative(f.path, from: config.pathConfig.getExportDir());
    var incrFile = File(
      path.join(
        config.pathConfig.incrDir,
        path.dirname(rel),
        path.basename(f.path) + '.timestamp',
      ),
    );
    if (autoCreateDirectory) {
      await Directory(path.dirname(incrFile.path)).create(recursive: true);
    }
    return incrFile;
  }
  return null;
}

Future<bool> isFileModified(ExportConfig config, File f) async {
  var incrFile = await _incrementalRecordFile(config, f, false);
  if (incrFile != null) {
    if (await incrFile.exists()) {
      var srcTime = (await f.lastModified()).millisecondsSinceEpoch;
      var lastTime = int.tryParse(await incrFile.readAsString(), radix: 36);
      return lastTime == null || srcTime != lastTime;
    }
  }
  return true;
}

Future recordFileTimestamp(ExportConfig config, File f) async {
  var incrFile = await _incrementalRecordFile(config, f, true);
  if (incrFile != null) {
    await incrFile.writeAsString(
      (await f.lastModified()).millisecondsSinceEpoch.toRadixString(36),
    );
  }
}
