import 'dart:io';
import 'package:dl_datamine/dlmanifest.dart';
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

Future<ManifestAssetBundle> pullAsset(ManifestAssetBundle asset, {bool useName = false}) async {
  if (useName) {
    asset.file =
        File(path.joinAll([_assetsPath, '.named', ...asset.name.split('/')]));
  } else {
    asset.file =
        File(path.join(_assetsPath, asset.hash.substring(0, 2), asset.hash));
  }
  await asset.file.parent.create(recursive: true);

  checkExists:
  if (await asset.file.exists()) {
    if (asset.size != await asset.file.length()) break checkExists;
    return asset;
  }

  var bytes;
  try {
    bytes = await http.readBytes(_assetUrl(asset.hash));
  } on SocketException {
    return pullAsset(asset, useName: useName);
  }

  print('${DateTime.now().toIso8601String()}: [cdn] pulled ${asset.hash} ...');
  await asset.file.writeAsBytes(bytes);
  return asset;
}
