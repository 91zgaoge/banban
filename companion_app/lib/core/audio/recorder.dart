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
  Future<bool> requestPermission() => _rec.hasPermission();

  /// Start recording Opus audio (16 kHz, mono) to a temp file.
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/banban_${DateTime.now().millisecondsSinceEpoch}.opus';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  /// Stop recording and return raw audio bytes, or null on error.
  Future<List<int>?> stop() async {
    final path = await _rec.stop();
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    file.delete().ignore();
    return bytes;
  }

  /// Whether a recording is currently in progress.
  Future<bool> get isRecording => _rec.isRecording();

  Future<void> dispose() => _rec.dispose();
}
