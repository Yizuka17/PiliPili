import 'dart:async';

import 'package:Pilipili/services/windows_smtc.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAudioHandler extends BaseAudioHandler {
  final commands = <String>[];
  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> skipToNext() async => commands.add('next');
  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inMilliseconds}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pilipili/smtc_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late WindowsSmtc smtc;
  late RecordingAudioHandler handler;
  Future<void> command(String name, [Object? argument]) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(name, argument)),
      (ByteData? _) => done.complete(),
    );
    await done.future;
  }

  Future<void> drain() => Future<void>.delayed(Duration.zero);

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    smtc = WindowsSmtc(
      channel: channel,
      supported: true,
      artworkLoader: (_) async => null,
    );
    handler = RecordingAudioHandler();
    smtc.bind(handler);
  });
  tearDown(() {
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
  });
  final item = MediaItem(
    id: 'video',
    title: '测试标题',
    artist: '测试作者',
    duration: const Duration(seconds: 100),
    artUri: Uri.parse('https://example.com/cover.jpg'),
  );

  test('disabled by default; caches metadata without publishing or controlling playback', () async {
    smtc.setMediaItem(item);
    smtc.updatePlayback(PlaybackState(processingState: .ready, playing: true));
    await command('play');
    await drain();
    expect(smtc.enabled, isFalse);
    expect(calls, isEmpty);
    expect(handler.commands, isEmpty);
  });

  test('enable mid-play publishes artwork and metadata; disable removes the session', () async {
    smtc.setMediaItem(item);
    smtc.updatePlayback(
      PlaybackState(
        processingState: .ready,
        playing: true,
        updatePosition: const Duration(seconds: 12),
      ),
    );
    await smtc.setEnabled(true);
    final metadata = calls.last.arguments as Map;
    expect(metadata['title'], item.title);
    expect(metadata['artist'], item.artist);
    expect(metadata['artwork'], item.artUri.toString());
    expect(metadata['playing'], isTrue);
    expect(metadata['positionMs'], 12000);
    await command('pause');
    await command('seek', 120000);
    expect(handler.commands, ['pause', 'seek:100000']);
    await smtc.setEnabled(false);
    expect(calls.last.method, 'setEnabled');
    expect(calls.last.arguments, isFalse);
    await command('play');
    expect(handler.commands, ['pause', 'seek:100000']);
  });

  test(
    'live streams cannot seek; clear prevents stale media commands',
    () async {
      smtc.setMediaItem(const MediaItem(id: 'live', title: '直播', isLive: true));
      smtc.updatePlayback(
        PlaybackState(processingState: .ready, playing: true),
      );
      await smtc.setEnabled(true);
      expect((calls.last.arguments as Map)['canSkip'], isFalse);
      await command('seek', 1000);
      await command('next');
      expect(handler.commands, isEmpty);
      smtc.clear();
      await drain();
      expect(calls.last.arguments, isFalse);
      await command('play');
      expect(handler.commands, isEmpty);
    },
  );

  test(
    'cover loads once and does not block metadata or publish after disable',
    () async {
      final loaded = Completer<Uint8List?>();
      var loads = 0;
      smtc = WindowsSmtc(
        channel: channel,
        supported: true,
        artworkLoader: (_) {
          ++loads;
          return loaded.future;
        },
      );
      smtc.setMediaItem(item);
      smtc.updatePlayback(
        PlaybackState(processingState: .ready, playing: true),
      );
      expect(loads, 0);
      await smtc.setEnabled(true);
      expect(loads, 1);
      expect((calls.last.arguments as Map)['title'], item.title);
      expect((calls.last.arguments as Map)['artworkBytes'], isNull);
      smtc.updatePlayback(
        PlaybackState(processingState: .ready, playing: true),
      );
      await drain();
      expect(loads, 1);
      await smtc.setEnabled(false);
      loaded.complete(Uint8List.fromList([1, 2, 3]));
      await drain();
      expect(calls.last.method, 'setEnabled');
      expect(calls.last.arguments, isFalse);
    },
  );

  test('late previous cover cannot overwrite the next video cover', () async {
    final oldCover = Completer<Uint8List?>();
    final newCover = Completer<Uint8List?>();
    smtc = WindowsSmtc(
      channel: channel,
      supported: true,
      artworkLoader: (uri) =>
          uri == item.artUri ? oldCover.future : newCover.future,
    );
    smtc.setMediaItem(item);
    smtc.updatePlayback(PlaybackState(processingState: .ready, playing: true));
    await smtc.setEnabled(true);
    smtc.setMediaItem(
      item.copyWith(
        id: 'next-video',
        title: '下一条视频',
        artUri: Uri.parse('https://example.com/next.jpg'),
      ),
    );
    smtc.updatePlayback(PlaybackState(processingState: .ready, playing: true));
    oldCover.complete(Uint8List.fromList([1]));
    await drain();
    expect((calls.last.arguments as Map)['artworkBytes'], isNull);
    newCover.complete(Uint8List.fromList([2]));
    await drain();
    expect((calls.last.arguments as Map)['title'], '下一条视频');
    expect((calls.last.arguments as Map)['artworkBytes'], [2]);
  });

  test('cover failure preserves title and transport commands', () async {
    smtc = WindowsSmtc(
      channel: channel,
      supported: true,
      artworkLoader: (_) async => throw const FormatException('invalid image'),
    );
    smtc.bind(handler);
    smtc.setMediaItem(item);
    smtc.updatePlayback(PlaybackState(processingState: .ready, playing: true));
    await smtc.setEnabled(true);
    await drain();
    expect((calls.last.arguments as Map)['title'], item.title);
    await command('pause');
    expect(handler.commands, ['pause']);
  });
}
