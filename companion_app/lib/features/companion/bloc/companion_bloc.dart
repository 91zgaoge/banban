import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/websocket_client.dart';
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
/// Message flow:
///  CompanionMessageSent → add user msg → sendText()
///  WsStatusEvent        → isAssistantTyping = true
///  WsDeltaEvent         → append delta to streaming msg
///  WsFinalEvent         → finalize msg, isAssistantTyping = false
///  WsErrorEvent         → show error msg
class CompanionBloc extends Bloc<CompanionEvent, CompanionState> {
  CompanionBloc({
    required this.storage,
    required this.baseUrl,
  }) : super(const CompanionState()) {
    on<CompanionConnectRequested>(_onConnect);
    on<CompanionMessageSent>(_onMessageSent);
    on<CompanionWsEventReceived>(_onWsEvent);
    on<CompanionDisconnectRequested>(_onDisconnect);
  }

  final SecureStorageService storage;
  final String baseUrl;

  CompanionWebSocketClient? _client;
  StreamSubscription? _eventSub;

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

  void _onWsEvent(
    CompanionWsEventReceived event,
    Emitter<CompanionState> emit,
  ) {
    final wsEvent = event.event;
    switch (wsEvent) {
      case WsConnectedEvent():
        emit(state.copyWith(connectionStatus: ConnectionStatus.connected));

      case WsDisconnectedEvent():
        emit(state.copyWith(
          connectionStatus: ConnectionStatus.reconnecting,
        ));

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
        emit(state.copyWith(messages: msgs, isAssistantTyping: false));

      case WsErrorEvent(:final message):
        _streamingMsgId = null;
        emit(state.copyWith(
          isAssistantTyping: false,
          errorMessage: message,
        ));

      case WsPongEvent():
        break; // heartbeat ack — no UI update needed
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
    return super.close();
  }
}
