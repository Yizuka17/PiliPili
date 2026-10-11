import 'dart:io' show Platform;

import 'package:Pilipili/services/audio_handler.dart';
import 'package:Pilipili/services/audio_session.dart';
import 'package:Pilipili/services/windows_smtc.dart';
import 'package:Pilipili/utils/storage_pref.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;

Future<void> setupServiceLocator() async {
  // Windows uses our native SMTC bridge; audio_service/audio_session only
  // provide native platform services on the mobile and macOS paths.
  final audio = Platform.isWindows
      ? VideoPlayerServiceHandler()
      : await initAudioService();
  videoPlayerServiceHandler = audio;
  await WindowsSmtc.instance.setEnabled(Pref.enableSmtc);
  if (!Platform.isWindows) audioSessionHandler = AudioSessionHandler();
}
