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
    smtc = WindowsSmtc(channel: channel, supported: true);
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
}
