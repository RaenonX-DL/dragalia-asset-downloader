import 'dart:core';

import 'package:dl_datamine/dlcdn.dart' as cdn;
import 'package:dl_datamine/dlexport.dart' as exporter;
import 'package:dl_datamine/dlcontext.dart' as context;
import 'package:dl_datamine/dlimgproc.dart' as imgproc;

extension DurationExtension on Duration {
  String toHmsString() {
    var s = inSeconds;
    if (s == 0) {
      var fraction = inMilliseconds.toString().padLeft(3, '0');
      return '0.${fraction}s';
    }
    if (s >= 60) {
      var m = (s / 60).floor();
      s %= 60;
      if (m >= 60) {
        var h = (m / 60).floor();
        m %= 60;
        return '${h}h${m}m${s}s';
      }
      return '${m}m${s}s';
    }
    return '${s}s';
  }
}

void main(List<String> arguments) async {
  var config = await context.initWithArguments(arguments);

  var dumpStartTime = DateTime.now();

  await cdn.initialize(config);
  await cdn.downloadAllManifest();
  await exporter.exportAllAssets(config);
  await imgproc.composeAlpha(config);

  var dumpDuration = DateTime.now().difference(dumpStartTime).abs();
  print('${DateTime.now().toIso8601String()}: '
      'dump succeed in ${dumpDuration.toHmsString()}');
}
