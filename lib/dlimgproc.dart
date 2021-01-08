import 'dart:io';
import 'package:dl_datamine/dlcontext.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

Future compose_all_alpha() async {
  var srcDir = Directory(exportOutputDir);
  if (!await srcDir.exists()) return;

  var files = await srcDir.list(recursive: true).toSet();

  var filesToProcess = files.where((f) {
    if (f is File) {
      var ext = path.extension(f.path);
      if (ext.toLowerCase() != '.png') return false;
      var name = path.basenameWithoutExtension(f.path);
      if (name.endsWith('_alphaA8')) return false;
      return true;
    }
    return false;
  }).toList();

  var fileChunkCount = 50;
  var fileChunks = List.generate(fileChunkCount, (_) => []);

  for (var i = 0; i < filesToProcess.length; i += 1) {
    fileChunks[i % fileChunkCount].add(filesToProcess[i]);
  }

  print('::group::Compose image alpha channel');
  var dumpStartTime = DateTime.now();

  await Future.wait(fileChunks.map((fileChunk) async => {
    for (var file in fileChunk) {await compose_rgb_alpha(file)}
  }));

  var duration = DateTime.now().difference(dumpStartTime).abs();
  print('Image composing completed in ${duration}');
  print('::endgroup::');
}

Future compose_rgb_alpha(File file) async {
  var ext = path.extension(file.path);
  if (ext.toLowerCase() == '.png') {
    var name = path.basenameWithoutExtension(file.path);
    if (!name.endsWith('_alphaA8')) {
      var dir = path.dirname(file.path);
      var alphaFile = File(path.join(dir, '${name}_alphaA8.png'));
      if (await alphaFile.exists()) {
        if (await isFileModified(file)) {
          var currentDateTime = DateTime.now().toIso8601String();
          print('${currentDateTime}: [imgproc] compose alpha: ' + file.path);
          var rgb = img.decodePng(await file.readAsBytes());
          var a = img.decodePng(await alphaFile.readAsBytes());
          if (a.length != rgb.length) {
            a = img.copyResize(a,
                width: rgb.width,
                height: rgb.height,
                interpolation: img.Interpolation.average);
          }
          for (var i = 0; i < rgb.length; ++i) {
            rgb[i] = img.setAlpha(rgb[i], img.getAlpha(a[i]));
          }
          await file.writeAsBytes(img.encodePng(rgb));
          await recordFileTimestamp(file);
        }
      }
    }
  }
}
