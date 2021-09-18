import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import 'config.dart';
import 'dlcontext.dart';
import 'dlimgproc.dart';

class Coordinate {
  final int x;
  final int y;

  Coordinate._(this.x, this.y);
}

Future cropPartsImage(ExportConfig config, Set<FileSystemEntity> files) async {
  await performImageTask(
      config,
      files,
      (fileName) => fileName.endsWith('_base'),
      _cropPartsBase,
      'Crop parts from base',
      useAsync: true);
}

Future _cropPartsBase(ExportConfig config, File file) async {
  var dir = path.dirname(file.path);
  var name = path.basenameWithoutExtension(file.path);
  var baseName = name.replaceFirst('_base', '');

  var currentDateTime = DateTime.now().toIso8601String();
  print('$currentDateTime: [imgproc] crop parts base: ' + file.path);

  var baseTopLeftCoord =
      await _baseTopLeftCoord(File(path.join(dir, '$baseName.json')));

  try {
    var image = img.decodePng(await file.readAsBytes());

    if (image == null) {
      throw ArgumentError('Image file not loadable');
    }

    var cropped =
        img.copyCrop(image, baseTopLeftCoord.x, baseTopLeftCoord.y, 256, 256);

    var croppedFile = File(path.join(dir, '$baseName.png'));
    await croppedFile.writeAsBytes(img.encodePng(cropped));
  } on RangeError {
    throw RangeError(file.path);
  }
  await recordFileTimestamp(config, file);
}

Future<Coordinate> _baseTopLeftCoord(File partsConfig) async {
  var config = jsonDecode(await partsConfig.readAsString());

  var coord;
  try {
    coord = config['partsDataTable'][0]['position'];
  } on RangeError {
    throw RangeError(partsConfig.path);
  }

  // 128 is the fixed offset for some reason
  return Coordinate._(((coord['x'] as double) - 128).round(),
      ((coord['y'] as double) - 128).round());
}
