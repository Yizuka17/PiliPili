import 'package:Pilipili/services/audio_handler.dart';
import 'package:Pilipili/services/audio_session.dart';
import 'package:Pilipili/services/windows_smtc.dart';
import 'package:Pilipili/utils/storage_pref.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;

Future<void> setupServiceLocator() async {
  final audio = await initAudioService();
  videoPlayerServiceHandler = audio;
  await WindowsSmtc.instance.setEnabled(Pref.enableSmtc);
  audioSessionHandler = AudioSessionHandler();
}
