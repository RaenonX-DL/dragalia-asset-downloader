import 'dart:io';

import 'package:dl_datamine/config.dart';
import 'package:dl_datamine/dlmanifest.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'dlcontext.dart';

class CdnInfo {
  final String manifestPath;
  final String assetsPath;

  CdnInfo._(this.manifestPath, this.assetsPath);

  String manifestAssetPath([String? locale]) {
    locale ??= manifestMasterLocale;
    return path.join(manifestPath, manifestLocaleFiles[locale]);
  }
}

Uri _manifestUrl(String file) {
  return Uri.https(cdnBaseUrl.authority,
      '${cdnBaseUrl.path}/manifests/Android/$versionCode/$file');
}

Uri _assetUrl(String hash) {
  return Uri.https(cdnBaseUrl.authority,
      '$cdnBaseUrl/assetbundles/Android/${hash.substring(0, 2)}/$hash');
}

Future<CdnInfo> initialize(ExportConfig config) async {
  var manifestPath =
      path.join(config.pathConfig.cdnDir, 'manifest', versionCode);
  var assetsPath = path.join(config.pathConfig.cdnDir, 'assets');

  await Directory(manifestPath).create(recursive: true);
  await Directory(assetsPath).create(recursive: true);

  for (var file in manifestLocaleFiles.values) {
    var bytes = await http.readBytes(_manifestUrl(file));
    await File(path.join(manifestPath, file)).writeAsBytes(bytes, flush: true);
  }

  return CdnInfo._(manifestPath, assetsPath);
}

String manifestJsonPath(String rootDir, String locale) {
  return path.join(rootDir, 'assets', 'manifest.json');
}

Future<ManifestAssetBundle> pullAsset(
    CdnInfo cdnInfo, ManifestAssetBundle asset,
    {bool? useName}) async {
  if (useName ?? false) {
    asset.file = File(
        path.joinAll([cdnInfo.assetsPath, '.named', ...asset.name.split('/')]));
  } else {
    asset.file = File(
        path.join(cdnInfo.assetsPath, asset.hash.substring(0, 2), asset.hash));
  }
  await asset.file!.parent.create(recursive: true);

  checkExists:
  if (await asset.file!.exists()) {
    if (asset.size != await asset.file!.length()) break checkExists;
    return asset;
  }

  var bytes;
  try {
    bytes = await http.readBytes(_assetUrl(asset.hash));
  } on SocketException {
    return pullAsset(cdnInfo, asset, useName: useName);
  }

  print('${DateTime.now().toIso8601String()}: [cdn] pulled ${asset.hash} ...');
  await asset.file!.writeAsBytes(bytes);
  return asset;
}
