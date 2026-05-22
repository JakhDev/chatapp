import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

// path_provider faqat mobile uchun import qilamiz
import 'package:path_provider/path_provider.dart'
if (dart.library.html) 'package:chatapp/services/path_provider_stub.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer   _player   = AudioPlayer();

  Future<bool> startRecording() async {
    // ✅ Web da audio recording ishlamaydi
    if (kIsWeb) {
      return false;
    }

    try {
      if (!await _recorder.hasPermission()) return false;
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      return true;
    } catch (e) {
      print('❌ Recording error: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (kIsWeb) return null;
    try {
      return await _recorder.stop();
    } catch (e) {
      print('❌ Stop recording error: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (kIsWeb) return;
    try {
      await _recorder.cancel();
    } catch (e) {
      print('❌ Cancel error: $e');
    }
  }

  Future<void> play(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      print('❌ Play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<Duration?> getDuration(String url) async {
    try {
      await _player.setUrl(url);
      return _player.duration;
    } catch (e) {
      return null;
    }
  }

  Stream<Duration> getPositionStream() => _player.positionStream;
  Stream<PlayerState> getStateStream()  => _player.playerStateStream;

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}