import 'dart:io';

import 'config.dart';

Future<Set<FileSystemEntity>> getExportedFiles(ExportConfig config) async {
  var srcDir = Directory(config.pathConfig.getExportDir());
  if (!await srcDir.exists()) {
    await srcDir.create(recursive: true);
  }

  return await srcDir.list(recursive: true).toSet();
}
