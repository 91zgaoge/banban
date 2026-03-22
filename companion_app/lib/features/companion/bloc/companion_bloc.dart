import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/audio/player.dart';
import '../../../core/auth/secure_storage.dart';
import '../models/chat_message.dart';
import 'companion_event.dart';
import 'companion_state.dart';

const _uuid = Uuid();

/// Manages the companion conversation state and WebSocket lifecycle.
///
/// State machine:
///
///  [disconnected]
///      │  CompanionConnectRequested
///      ▼
///  [connected] ◄─── WsConnectedEvent (reconnect)
///      │  WsDisconnectedEvent
///      ▼
///  [reconnecting] ──► [connected] (auto)
///
/// Message flow (text):
///  CompanionMessageSent → add user msg → sendText()
///  WsStatusEvent        → isAssistantTyping = true
///  WsDeltaEvent         → append delta to streaming msg
///  WsFinalEvent         → finalize msg, isAssistantTyping = false
///  WsErrorEvent         → show error msg
///
/// Message flow (voice / PTT):
///  VoiceRecordStarted  → isRecording = true
///  VoiceRecordStopped  → sendAudio() → isRecording = false
///  WsTranscriptionEvent → add user bubble, clear transcriptionText
///  (then same as text flow for assistant reply)
///
/// TTS playback:
///  WsTtsChunkEvent → TtsPlayer.addChunk()
///  WsTtsDoneEvent  → TtsPlayer.markDone() → isTtsPlaying = true
class CompanionBloc extends Bloc<CompanionEvent, CompanionState> {
  CompanionBloc({
    required this.storage,
    required this.baseUrl,
  }) : super(const CompanionState()) {
    on<CompanionConnectRequested>(_onConnect);
    on<CompanionMessageSent>(_onMessageSent);
    on<CompanionWsEventReceived>(_onWsEvent);
    on<CompanionDisconnectRequested>(_onDisconnect);
    on<VoiceRecordStarted>(_onVoiceRecordStarted);
    on<VoiceRecordStopped>(_onVoiceRecordStopped);
    on<VoiceRecordCancelled>(_onVoiceRecordCancelled);
  }

  final SecureStorageService storage;
  final String baseUrl;

  CompanionWebSocketClient? _client;
  StreamSubscription? _eventSub;
  final _ttsPlayer = TtsPlayer();

  // Tracks the id of the currently streaming assistant message.
  String? _streamingMsgId;

  Future<void> _onConnect(
    CompanionConnectRequested event,
    Emitter<CompanionState> emit,
  ) async {
    _disposeClient();
    final token = await storage.readToken();
    if (token == null) return;

    final wsUrl = _buildWsUrl(baseUrl, event.botId, token);
    _client = CompanionWebSocketClient(wsUrl: wsUrl);

    _eventSub = _client!.events.listen((wsEvent) {
      if (!isClosed) add(CompanionWsEventReceived(wsEvent));
    });

    _client!.connect();
    emit(state.copyWith(
      botId: event.botId,
      connectionStatus: ConnectionStatus.reconnecting,
      clearError: true,
    ));
  }

  void _onMessageSent(
    CompanionMessageSent event,
    Emitter<CompanionState> emit,
  ) {
    if (_client == null) return;
    final text = event.text.trim();
    if (text.isEmpty) return;

    final msg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: text,
      status: MessageStatus.complete,
      createdAt: DateTime.now(),
    );
    emit(state.copyWith(messages: [...state.messages, msg], clearError: true));
    _client!.sendText(text);
  }

  void _onVoiceRecordStarted(
    VoiceRecordStarted event,
    Emitter<CompanionState> emit,
  ) {
    emit(state.copyWith(isRecording: true, clearError: true));
  }

  void _onVoiceRecordStopped(
    VoiceRecordStopped event,
    Emitter<CompanionState> emit,
  ) {
    emit(state.copyWith(isRecording: false));
    if (_client == null || event.audioBytes.isEmpty) return;
    // Stop any in-flight TTS and send audio to server.
    _ttsPlayer.stop();
    _client!.sendAudio(event.audioBytes, codec: 'opus', isFinal: true);
  }

  void _onVoiceRecordCancelled(
    VoiceRecordCancelled event,
    Emitter<CompanionState> emit,
  ) {
    emit(state.copyWith(isRecording: false));
  }

  void _onWsEvent(
    CompanionWsEventReceived event,
    Emitter<CompanionState> emit,
  ) {
    final wsEvent = event.event;
    switch (wsEvent) {
      case WsConnectedEvent():
        emit(state.copyWith(connectionStatus: ConnectionStatus.connected));

      case WsDisconnectedEvent():
        emit(state.copyWith(connectionStatus: ConnectionStatus.reconnecting));

      case WsStatusEvent(:final status):
        if (status == 'thinking') {
          _streamingMsgId = _uuid.v4();
          final msg = ChatMessage(
            id: _streamingMsgId!,
            role: MessageRole.assistant,
            text: '',
            status: MessageStatus.thinking,
            createdAt: DateTime.now(),
          );
          emit(state.copyWith(
            messages: [...state.messages, msg],
            isAssistantTyping: true,
          ));
        }

      case WsDeltaEvent(:final text):
        if (_streamingMsgId == null) {
          _streamingMsgId = _uuid.v4();
          final msg = ChatMessage(
            id: _streamingMsgId!,
            role: MessageRole.assistant,
            text: text,
            status: MessageStatus.streaming,
            createdAt: DateTime.now(),
          );
          emit(state.copyWith(messages: [...state.messages, msg]));
        } else {
          final updated = state.messages.map((m) {
            if (m.id == _streamingMsgId) {
              return m.copyWith(text: m.text + text, status: MessageStatus.streaming);
            }
            return m;
          }).toList();
          emit(state.copyWith(messages: updated, isAssistantTyping: false));
        }

      case WsFinalEvent(:final text, :final durationMs):
        final msgs = state.messages.map((m) {
          if (m.id == _streamingMsgId) {
            return m.copyWith(
              text: text.isNotEmpty ? text : m.text,
              status: MessageStatus.complete,
              durationMs: durationMs,
            );
          }
          return m;
        }).toList();
        _streamingMsgId = null;
        emit(state.copyWith(
          messages: msgs,
          isAssistantTyping: false,
          clearTranscription: true,
        ));

      case WsErrorEvent(:final message):
        _streamingMsgId = null;
        emit(state.copyWith(isAssistantTyping: false, errorMessage: message));

      case WsPongEvent():
        break; // heartbeat ack

      case WsTranscriptionEvent(:final text):
        // Add a user bubble with the recognised speech text.
        if (text.isNotEmpty) {
          final msg = ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.user,
            text: text,
            status: MessageStatus.complete,
            createdAt: DateTime.now(),
          );
          emit(state.copyWith(
            messages: [...state.messages, msg],
            transcriptionText: text,
          ));
        }

      case WsTtsChunkEvent(:final seq, :final audio):
        _ttsPlayer.addChunk(seq, audio);

      case WsTtsDoneEvent(:final seq):
        _ttsPlayer.markDone(seq);
        emit(state.copyWith(isTtsPlaying: true));

      case WsTtsErrorEvent():
        // Ignore TTS errors silently (text is still shown).
        break;

      case WsProactiveEvent(:final text):
        if (text.isNotEmpty) {
          final msg = ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            text: text,
            status: MessageStatus.complete,
            createdAt: DateTime.now(),
          );
          emit(state.copyWith(messages: [...state.messages, msg]));
        }
    }
  }

  void _onDisconnect(
    CompanionDisconnectRequested event,
    Emitter<CompanionState> emit,
  ) {
    _disposeClient();
    emit(state.copyWith(connectionStatus: ConnectionStatus.disconnected));
  }

  void _disposeClient() {
    _eventSub?.cancel();
    _client?.dispose();
    _client = null;
    _streamingMsgId = null;
  }

  String _buildWsUrl(String baseUrl, String botId, String token) {
    final base = baseUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .trimRight();
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://$base/bots/$botId/companion/ws?token=${Uri.encodeComponent(token)}';
  }

  @override
  Future<void> close() {
    _disposeClient();
    _ttsPlayer.dispose();
    return super.close();
  }
}
