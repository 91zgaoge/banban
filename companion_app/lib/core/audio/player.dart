import 'dart:collection';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// Plays streamed TTS audio chunks in sequence order.
///
/// The backend sends:
///   tts_chunk {seq, chunk, audio}  — incremental WAV bytes for sentence N
///   tts_done  {seq}               — sentence N is fully sent
///
/// TtsPlayer buffers chunks per seq, plays them in order when tts_done arrives.
class TtsPlayer {
  final _player = AudioPlayer();

  // seq → accumulated WAV bytes
  final _buffers = <int, List<int>>{};

  // seqs that are ready (tts_done received) but not yet played
  final _readyQueue = Queue<int>();

  bool _isPlaying = false;

  /// Called for each incoming tts_chunk frame.
  void addChunk(int seq, Uint8List data) {
    _buffers.putIfAbsent(seq, () => []).addAll(data);
  }

  /// Called when tts_done arrives for [seq].
  void markDone(int seq) {
    if (!_buffers.containsKey(seq)) return;
    _readyQueue.add(seq);
    if (!_isPlaying) _playNext();
  }

  Future<void> _playNext() async {
    if (_readyQueue.isEmpty) {
      _isPlaying = false;
      return;
    }
    _isPlaying = true;
    final seq = _readyQueue.removeFirst();
    final bytes = _buffers.remove(seq);
    if (bytes == null || bytes.isEmpty) {
      _playNext();
      return;
    }

    try {
      final uri = Uri.dataFromBytes(
        Uint8List.fromList(bytes),
        mimeType: 'audio/wav',
      );
      await _player.setAudioSource(AudioSource.uri(uri));
      await _player.play();
      // Wait until playback completes.
      await _player.playerStateStream.firstWhere(
        (s) =>
            s.processingState == ProcessingState.completed ||
            s.processingState == ProcessingState.idle,
      );
      await _player.stop();
    } catch (_) {
      // Ignore playback errors; continue with next.
    }

    _playNext();
  }

  /// Stop all playback and clear pending buffers.
  Future<void> stop() async {
    _isPlaying = false;
    _readyQueue.clear();
    _buffers.clear();
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
