import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:Pilipili/common/constants.dart';
import 'package:Pilipili/http/constants.dart';
import 'package:Pilipili/utils/cache_manager.dart';

/// Supply decoded PNG bytes so Windows never has to fetch or decode WebP itself.
Future<Uint8List?> loadSmtcArtwork(Uri uri) async {
  final File file;
  if (uri.scheme == 'file') {
    file = File.fromUri(uri);
  } else if (uri.scheme == 'https' || uri.scheme == 'http') {
    file = await CacheManager.manager.getSingleFile(
      uri.toString(),
      headers: const {
        'Referer': HttpString.baseUrl,
        'User-Agent': Constants.userAgent,
      },
    );
  } else {
    return null;
  }
  return smtcArtworkToPng(await file.readAsBytes());
}

Future<Uint8List?> smtcArtworkToPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 320,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
