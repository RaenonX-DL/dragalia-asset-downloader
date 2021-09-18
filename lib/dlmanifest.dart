import 'dart:io';

import 'dlcdn.dart' as cdn;

class ManifestAssetBundle {
  String name;
  String hash;
  int size;
  File? file;

  ManifestAssetBundle(this.name, this.hash, this.size, this.file);

  factory ManifestAssetBundle.parse(Map<String, dynamic> entry) {
    return ManifestAssetBundle(
        entry['name'], entry['hash'], entry['size'], null);
  }
}

class Manifest {
  Map<String, ManifestAssetBundle> unityAssets;
  Map<String, ManifestAssetBundle> rawAssets;

  Manifest._(this.unityAssets, this.rawAssets);

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

  Future<ManifestAssetBundle> pullUnityAsset(cdn.CdnInfo cdnInfo, String name) {
    var asset = unityAssets[name];
    if (asset == null) {
      return Future.error(Exception('asset $name is not found in manifest'));
    }
    return cdn.pullAsset(cdnInfo, asset);
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullUnityAssets(
      cdn.CdnInfo cdnInfo, RegExp expr,
      {bool Function(ManifestAssetBundle)? filter}) {
    return pullAssets(
        cdnInfo, selectAssetsRegExp(unityAssets, expr, filter: filter));
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullRawAssets(
      cdn.CdnInfo cdnInfo, RegExp expr,
      {bool Function(ManifestAssetBundle)? filter}) {
    return pullAssets(
        cdnInfo, selectAssetsRegExp(rawAssets, expr, filter: filter),
        useName: true);
  }

  Iterable<ManifestAssetBundle> selectAssetsRegExp(
      Map<String, ManifestAssetBundle> assets, RegExp expr,
      {bool Function(ManifestAssetBundle)? filter}) {
    var assetsIter =
        assets.entries.where((e) => expr.hasMatch(e.key)).map((e) => e.value);

    if (filter != null) {
      assetsIter = assetsIter.where(filter);
    }

    return assetsIter;
  }

  Iterable<Future<List<ManifestAssetBundle>>> pullAssets(
      cdn.CdnInfo cdnInfo, Iterable<ManifestAssetBundle> assets,
      {bool? useName}) {
    var assetChunkSize = 50;
    var assetChunks = <List<ManifestAssetBundle>>[];

    for (var start = 0; start < assets.length; start += assetChunkSize) {
      assetChunks.add(assets.skip(start).take(assetChunkSize).toList());
    }

    return assetChunks.map((assetChunk) => Future.wait(assetChunk
        .map((asset) => cdn.pullAsset(cdnInfo, asset, useName: useName))));
  }
}
