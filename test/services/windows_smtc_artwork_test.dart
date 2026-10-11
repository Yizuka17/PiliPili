import 'dart:io';
import 'dart:ui' as ui;

import 'package:Pilipili/services/windows_smtc_artwork.dart';
import 'package:Pilipili/common/constants.dart';
import 'package:Pilipili/http/constants.dart';
import 'package:Pilipili/utils/cache_manager.dart' as app_cache;
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';

class _ArtworkHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local WebP cover becomes a bounded PNG readable by system controls',
    () async {
      final file = File('test/fixtures/smtc_cover.webp');
      final png = (await loadSmtcArtwork(file.absolute.uri))!;
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(png);
      try {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 320);
        expect(frame.image.height, 160);
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    },
  );

  test(
    'network WebP cover uses request headers and the existing image cache',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final directory = await Directory.systemTemp.createTemp(
          'pili-cover-cache-',
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final webp = await File('test/fixtures/smtc_cover.webp').readAsBytes();
        var requests = 0;
        String? referer;
        String? userAgent;
        server.listen((request) async {
          ++requests;
          referer = request.headers.value('referer');
          userAgent = request.headers.value('user-agent');
          request.response
            ..headers.set('content-type', 'image/webp')
            ..headers.set('cache-control', 'max-age=3600')
            ..contentLength = webp.length
            ..add(webp);
          await request.response.close();
        });
        final manager = await DefaultCacheManager.init(
          cacheDirectoryProvider: () async => directory,
        );
        app_cache.CacheManager.manager = manager;
        try {
          final uri = Uri.parse('http://127.0.0.1:${server.port}/cover.webp');
          final first = (await loadSmtcArtwork(uri))!;
          final second = (await loadSmtcArtwork(uri))!;
          expect(first.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
          expect(second, first);
          expect(requests, 1);
          expect(referer, HttpString.baseUrl);
          expect(userAgent, Constants.userAgent);
        } finally {
          await manager.dispose();
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      }, _ArtworkHttpOverrides());
    },
  );
}
