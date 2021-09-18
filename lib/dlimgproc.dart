import 'dart:io';
import 'dart:math';

import 'package:dl_datamine/config.dart';
import 'package:dl_datamine/dlcontext.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

Future composeImage(ExportConfig config) async {
  var srcDir = Directory(config.pathConfig.getExportDir());
  if (!await srcDir.exists()) {
    await srcDir.create(recursive: true);
  }

  var files = await srcDir.list(recursive: true).toSet();

  await _performImageTask(
      config,
      files,
      (fileName) => !fileName.endsWith('_alphaA8') && !fileName.endsWith('_Y'),
      _composeRgbAlphaSingle,
      'Merge Alpha',
      useAsync: true);
  // Async causes some problem during merger
  await _performImageTask(config, files, (fileName) => fileName.endsWith('_Y'),
      _composeYCbCrSingle, 'Merge YCbCr',
      useAsync: true);
}

Future _performImageTask(
  ExportConfig config,
  Set<FileSystemEntity> files,
  Function(String) isFileNameToUse,
  Future Function(ExportConfig config, File file) fnComposeSingle,
  String taskName, {
  bool useAsync = true,
}) async {
  var filesToProcess = files.where((f) {
    if (f is File) {
      var ext = path.extension(f.path);
      if (ext.toLowerCase() != '.png') return false;
      var name = path.basenameWithoutExtension(f.path);
      return isFileNameToUse(name);
    }
    return false;
  }).toList();

  var fileChunkCount = useAsync ? sqrt(filesToProcess.length).round() : 1;
  var fileChunks = List.generate(fileChunkCount, (_) => []);

  for (var i = 0; i < filesToProcess.length; i += 1) {
    fileChunks[i % fileChunkCount].add(filesToProcess[i]);
  }

  print('::group::Compose image - ${taskName}');
  var dumpStartTime = DateTime.now();

  await Future.wait(fileChunks.map((fileChunk) async => {
        for (var file in fileChunk)
          {
            if (await isFileModified(config, file))
              {await fnComposeSingle(config, file)}
          }
      }));

  var duration = DateTime.now().difference(dumpStartTime).abs();
  print('${taskName} completed in ${duration}');
  print('::endgroup::');
}

Future _composeRgbAlphaSingle(ExportConfig config, File file) async {
  var dir = path.dirname(file.path);
  var name = path.basenameWithoutExtension(file.path);

  var alphaFile = File(path.join(dir, '${name}_alphaA8.png'));
  if (!await alphaFile.exists()) {
    return;
  }

  var currentDateTime = DateTime.now().toIso8601String();
  print('${currentDateTime}: [imgproc] compose alpha: ' + file.path);

  try {
    var rgb = img.decodePng(await file.readAsBytes());
    var a = img.decodePng(await alphaFile.readAsBytes());

    if (a.length != rgb.length) {
      a = _resizeImage(a, rgb);
    }

    for (var i = 0; i < rgb.length; ++i) {
      rgb[i] = img.setAlpha(rgb[i], img.getAlpha(a[i]));
    }

    await file.writeAsBytes(img.encodePng(rgb));
  } on RangeError {
    throw RangeError(file.path);
  }
  await recordFileTimestamp(config, file);
}

Future _composeYCbCrSingle(ExportConfig config, File file) async {
  var dir = path.dirname(file.path);
  // Replace `_Y` to get the base image name
  var name = path.basenameWithoutExtension(file.path).replaceFirst('_Y', '');

  var yFile = File(path.join(dir, '${name}_Y.png'));
  var cbFile = File(path.join(dir, '${name}_Cb.png'));
  var crFile = File(path.join(dir, '${name}_Cr.png'));
  if (!await yFile.exists() ||
      !await cbFile.exists() ||
      !await crFile.exists()) {
    return;
  }

  var currentDateTime = DateTime.now().toIso8601String();
  print('${currentDateTime}: [imgproc] compose YCbCr: ' + file.path);

  try {
    var yImage = img.decodePng(await yFile.readAsBytes());
    var cbImage = img.decodePng(await cbFile.readAsBytes());
    var crImage = img.decodePng(await crFile.readAsBytes());

    if (cbImage.length != yImage.length) {
      cbImage = _resizeImage(cbImage, yImage);
    }
    if (crImage.length != yImage.length) {
      crImage = _resizeImage(crImage, yImage);
    }

    for (var i = 0; i < yImage.length; ++i) {
      var yVal = img.getAlpha(yImage[i]);
      var cbVal = img.getLuminance(cbImage[i]);
      var crVal = img.getLuminance(crImage[i]);

      var rgb = _getRgbFromYCrCb(yVal, cbVal, crVal);

      yImage[i] = img.setRed(yImage[i], rgb[0]);
      yImage[i] = img.setGreen(yImage[i], rgb[1]);
      yImage[i] = img.setBlue(yImage[i], rgb[2]);
      // Alpha of `yImage` is not 0 or 255 across the image,
      // force set it to either transparent or not
      yImage[i] = img.setAlpha(yImage[i], yVal > 0 ? 255 : 0);
    }

    var outFile = File(file.path.replaceFirst('_Y', ''));
    await outFile.writeAsBytes(img.encodePng(yImage));
  } on RangeError {
    throw RangeError(file.path);
  }
  await recordFileTimestamp(config, file);
}

List<int> _getRgbFromYCrCb(int Y, int Cb, int Cr) {
  Cb = Cb - 128;
  Cr = Cr - 128;
  var r = max(0, min(255, (Y + 45 * Cr / 32).round()));
  var g = max(0, min(255, (Y - (11 * Cb + 23 * Cr) / 32).round()));
  var b = max(0, min(255, (Y + 113 * Cb / 64).round()));

  return List.from([r, g, b]);
}

img.Image _resizeImage(img.Image src, img.Image sizeBase) {
  return img.copyResize(src,
      width: sizeBase.width,
      height: sizeBase.height,
      interpolation: img.Interpolation.average);
}
