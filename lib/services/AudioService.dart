import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer   _player   = AudioPlayer();

  PlayerState _playerState = PlayerState.stopped;
  PlayerState get playerState => _playerState;

  AudioService() {
    _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
    });
  }

  // ── Recording ─────────────────────────────────────────
  Future<bool> startRecording() async {
    if (kIsWeb) return false;
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      return true;
    } catch (e) {
      debugPrint('❌ startRecording: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (kIsWeb) return null;
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint('❌ stopRecording: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (kIsWeb) return;
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('❌ cancelRecording: $e');
    }
  }

  // ── Playback ──────────────────────────────────────────
  Future<void> play(String url) async {
    try {
      await _player.play(UrlSource(url));
    } catch (e) {
      debugPrint('❌ play: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('❌ pause: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('❌ stop: $e');
    }
  }

  Future<Duration?> getDuration(String url) async {
    try {
      await _player.setSourceUrl(url);
      return _player.getDuration();
    } catch (e) {
      debugPrint('❌ getDuration: $e');
      return null;
    }
  }

  Stream<Duration> getPositionStream() => _player.onPositionChanged;

  Stream<void> getCompletedStream() => _player.onPlayerComplete;

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}