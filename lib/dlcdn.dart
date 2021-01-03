import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dlcontext.dart';

String _manifestUrl(String file) {
  return '$cdnBaseUrl/manifests/Android/$versionCode/$file';
}

String _assetUrl(String hash) {
  return '$cdnBaseUrl/assetbundles/Android/${hash.substring(0, 2)}/$hash';
}

String _manifestPath;
String _assetsPath;

Future initialize() async {
  _manifestPath = path.join(cdnOutputPath, 'manifest', versionCode);
  _assetsPath = path.join(cdnOutputPath, 'assets');
  await Directory(_manifestPath).create(recursive: true);
  await Directory(_assetsPath).create(recursive: true);
}

Future downloadAllManifest() async {
  for (var file in manifestLocaleFiles.values) {
    var bytes = await http.readBytes(_manifestUrl(file));
    await File(path.join(_manifestPath, file)).writeAsBytes(bytes, flush: true);
  }
}

String manifestPath([String locale]) {
  locale ??= manifestMasterLocale;
  return path.join(_manifestPath, manifestLocaleFiles[locale]);
}

Future<File> pullAsset(String hash, {int checkSize}) async {
  var saveToDir = Directory(path.join(_assetsPath, hash.substring(0, 2)));
  await saveToDir.create(recursive: true);
  var saveToFile = File(path.join(saveToDir.path, hash));

  checkExists:
  if (await saveToFile.exists()) {
    if (checkSize != null) {
      if (checkSize != await saveToFile.length()) break checkExists;
    }
    return saveToFile;
  }

  var bytes;
  try {
    bytes = await http.readBytes(_assetUrl(hash));
  } on SocketException {
    return pullAsset(hash, checkSize: checkSize);
  }

  print('${DateTime.now().toIso8601String()}: [cdn] pulled $hash ...');
  return await File(path.join(saveToDir.path, hash)).writeAsBytes(bytes);
}
