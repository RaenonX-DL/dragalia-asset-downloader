import 'dart:io';
import 'dart:math';

import 'dlcdn.dart' as cdn;

class ManifestAssetBundle {
  String name;
  String hash;
  int size;
  File file;

  ManifestAssetBundle(this.name, this.hash, this.size, this.file);

  factory ManifestAssetBundle.parse(Map<String, dynamic> entry) {
    return ManifestAssetBundle(
        entry['name'], entry['hash'], entry['size'], null);
  }
}

class Manifest {
  Map<String, ManifestAssetBundle> _unityAssets;
  Map<String, ManifestAssetBundle> _rawAssets;

  Manifest._(this._unityAssets, this._rawAssets);

  factory Manifest.fromJson(Map<String, dynamic> json) {
    var unityAssets = <String, ManifestAssetBundle>{};
    for (Map<String, dynamic> cat in json['categories'] as List) {
      var entries = (cat['assets'] as List)
          .map(
            (asset) => ManifestAssetBundle.parse(asset),
          )
          .map(
            (asset) => MapEntry(asset.name, asset),
          );
      unityAssets.addEntries(entries);
    }

    var rawAssetList = (json['rawAssets'] as List).map(
      (asset) => ManifestAssetBundle.parse(asset),
    );
    var rawAssets = {for (var v in rawAssetList) v.name: v};

    return Manifest._(unityAssets, rawAssets);
  }

  Future<ManifestAssetBundle> pullUnityAsset(String name) {
    var asset = _unityAssets[name];
    if (asset == null) {
      return Future.error(Exception('asset $name is not found in manifest'));
    }
    return cdn.pullAsset(asset);
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullUnityAssets(RegExp expr) {
    var assets = _unityAssets.entries
        .where((e) => expr.hasMatch(e.key))
        .map((e) => e.value)
        .toList();

    return pullAssets(assets);
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullRawAssets(RegExp expr) {
    var assets = _rawAssets.entries
        .where((e) => expr.hasMatch(e.key))
        .map((e) => e.value)
        .toList();

    return pullAssets(assets, useName: true);
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullAssets(
      List<ManifestAssetBundle> assets,
      {bool useName}) {
    var assetChunkSize = 50;
    var assetChunks = <List<ManifestAssetBundle>>[];

    for (var start = 0; start < assets.length; start += assetChunkSize) {
      assetChunks.add(
          assets.sublist(start, min(start + assetChunkSize, assets.length)));
    }

    return assetChunks.map((assetChunk) => Future.wait(
        assetChunk.map((asset) => cdn.pullAsset(asset, useName: useName))));
  }
}
