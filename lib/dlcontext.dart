import 'dart:io' as io;
import 'dart:io';
import 'package:path/path.dart' as path;

const bool kReleaseMode =
    bool.fromEnvironment('dart.vm.product', defaultValue: false);

const dotnetBin = 'dotnet';
const decryptedExtension = '.decrypted';
const cdnBaseUrl = 'https://dragalialost.akamaized.net/dl';

var exportOutputDir = 'media';
var cdnOutputPath = 'cdn';
var configPath = 'config.json';
var manifestIV = '';
var manifestKey = '';
var incrementalOutputPath = 'incr';
var tempOutputPath = 'temp';
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

String getArgumentsOptionValue(List<String> arguments, String flag) {
  var i = arguments.indexOf(flag);
  if (i >= 0 && i + 1 < arguments.length) {
    return arguments[i + 1];
  }
  return null;
}

Future initWithArguments(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('usage: dldump <VersionCode> '
        '[--export-path <path>] '
        '[--cdn-path <path>] '
        '[--config-path <path>]'
        '[--iv <iv>] '
        '[--key <key>] '
        '[--incr-path <path>]');
    io.exit(1);
  }

  var exportPath = getArgumentsOptionValue(arguments, '--export-path');
  if (exportPath != null) {
    var exportDir = Directory(path.normalize(exportPath));
    await exportDir.create(recursive: true);
    exportOutputDir = exportPath;
  }

  var cdnPath = getArgumentsOptionValue(arguments, '--cdn-path');
  if (cdnPath != null) {
    var cdnDir = Directory(path.normalize(cdnPath));
    await cdnDir.create(recursive: true);
    cdnOutputPath = cdnPath;
  }

  var config = getArgumentsOptionValue(arguments, '--config-path');
  if (config != null) {
    config = path.normalize(config);
    if (!await io.File(config).exists()) {
      print('config file not exists');
      io.exit(1);
    }
    configPath = config;
  }

  manifestIV = getArgumentsOptionValue(arguments, '--iv');
  if (manifestIV == null) {
    print('IV is required for decrypting the manifest');
    io.exit(1);
  }

  manifestKey = getArgumentsOptionValue(arguments, '--key');
  if (manifestKey == null) {
    print('Key is required for decrypting the manifest');
    io.exit(1);
  }

  var incrementalPath = getArgumentsOptionValue(arguments, '--incr-path');
  if (incrementalPath != null) {
    incrementalOutputPath = path.normalize(incrementalPath);
  }

  versionCode = arguments[0];
}

Future<File> _incrementalRecordFile(File f, bool autoCreateDirectory) async {
  if (path.isWithin(exportOutputDir, f.path)) {
    var rel = path.relative(f.path, from: exportOutputDir);
    var incrFile = File(
      path.join(
        incrementalOutputPath,
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

Future<bool> isFileModified(File f) async {
  var incrFile = await _incrementalRecordFile(f, false);
  if (incrFile != null) {
    if (await incrFile.exists()) {
      var srcTime = (await f.lastModified()).millisecondsSinceEpoch;
      var lastTime = int.tryParse(await incrFile.readAsString(), radix: 36);
      return lastTime == null || srcTime != lastTime;
    }
  }
  return true;
}

Future recordFileTimestamp(File f) async {
  var incrFile = await _incrementalRecordFile(f, true);
  if (incrFile != null) {
    await incrFile.writeAsString(
      (await f.lastModified()).millisecondsSinceEpoch.toRadixString(36),
    );
  }
}
