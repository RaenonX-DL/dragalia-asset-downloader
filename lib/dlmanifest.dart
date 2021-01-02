import 'dart:io';
import 'dlcdn.dart' as cdn;

class ManifestAssetBundle {
  String name;
  String hash;
  int size;

  ManifestAssetBundle(this.name, this.hash, this.size);
}

class Manifest {
  Map<String, ManifestAssetBundle> _namedAssetBundles;

  Manifest._(this._namedAssetBundles);

  factory Manifest.fromJson(Map<String, dynamic> json) {
    var namedAssetBundles = <String, ManifestAssetBundle>{};
    for (Map<String, dynamic> cat in json['categories'] as List) {
      var entries = (cat['assets'] as List)
          .map(
            (asset) => ManifestAssetBundle(
              asset['name'],
              asset['hash'],
              asset['size'],
            ),
          )
          .map(
            (asset) => MapEntry(asset.name, asset),
          );
      namedAssetBundles.addEntries(entries);
    }
    return Manifest._(namedAssetBundles);
  }

  Future<File> pullAsset(String name) {
    var asset = _namedAssetBundles[name];
    if (asset == null) {
      return Future.error(Exception('asset $name is not found in manifest'));
    }
    return cdn.pullAsset(
      asset.hash,
      checkSize: asset.size,
    );
  }

  Future<List<File>> pullAssets(RegExp expr) async {
    return Future.wait(_namedAssetBundles.entries
        .where((e) => expr.hasMatch(e.key))
        .map((asset) => cdn.pullAsset(
              asset.value.hash,
              checkSize: asset.value.size,
            )));
  }
}
