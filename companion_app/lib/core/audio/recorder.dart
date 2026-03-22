import 'dart:developer';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// PTT (push-to-talk) voice recorder using the `record` package.
///
/// Usage:
///   final recorder = VoiceRecorder();
///   await recorder.requestPermission();   // once, at startup
///   await recorder.start();               // user presses mic
///   final bytes = await recorder.stop();  // user releases mic → Opus bytes
class VoiceRecorder {
  final _rec = AudioRecorder();

  /// Returns true if microphone permission is granted.
  Future<bool> requestPermission() async {
    try {
      final hasPerm = await _rec.hasPermission();
      log('VoiceRecorder: permission check = $hasPerm');
      return hasPerm;
    } catch (e, st) {
      log('VoiceRecorder: permission check failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Start recording Opus audio (16 kHz, mono) to a temp file.
  /// Returns true if started successfully, false otherwise.
  Future<bool> start() async {
    try {
      // Double-check permission before starting
      final hasPerm = await _rec.hasPermission();
      if (!hasPerm) {
        log('VoiceRecorder: no permission to start recording');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/banban_${DateTime.now().millisecondsSinceEpoch}.opus';
      log('VoiceRecorder: starting recording to $path');

      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      log('VoiceRecorder: recording started successfully');
      return true;
    } catch (e, st) {
      log('VoiceRecorder: failed to start recording', error: e, stackTrace: st);
      return false;
    }
  }

  /// Stop recording and return raw audio bytes, or null on error.
  Future<List<int>?> stop() async {
    try {
      log('VoiceRecorder: stopping recording');
      final path = await _rec.stop();
      if (path == null) {
        log('VoiceRecorder: stop returned null path');
        return null;
      }
      final file = File(path);
      if (!file.existsSync()) {
        log('VoiceRecorder: recorded file does not exist at $path');
        return null;
      }
      final bytes = await file.readAsBytes();
      await file.delete();
      log('VoiceRecorder: stopped, got ${bytes.length} bytes');
      return bytes;
    } catch (e, st) {
      log('VoiceRecorder: failed to stop recording', error: e, stackTrace: st);
      return null;
    }
  }

  /// Whether a recording is currently in progress.
  Future<bool> get isRecording => _rec.isRecording();

  Future<void> dispose() => _rec.dispose();
}
