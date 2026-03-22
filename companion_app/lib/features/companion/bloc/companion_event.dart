import 'package:equatable/equatable.dart';

import '../../../core/api/websocket_client.dart';

sealed class CompanionEvent extends Equatable {
  const CompanionEvent();
  @override
  List<Object?> get props => [];
}

/// Connect to the companion WebSocket.
class CompanionConnectRequested extends CompanionEvent {
  const CompanionConnectRequested({required this.botId});
  final String botId;
  @override
  List<Object?> get props => [botId];
}

/// User sent a text message.
class CompanionMessageSent extends CompanionEvent {
  const CompanionMessageSent(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

/// Raw frame received from server.
class CompanionWsEventReceived extends CompanionEvent {
  const CompanionWsEventReceived(this.event);
  final WsEvent event;
  @override
  List<Object?> get props => [event];
}

/// User requested disconnect.
class CompanionDisconnectRequested extends CompanionEvent {}

/// User started holding the mic button (PTT start).
class VoiceRecordStarted extends CompanionEvent {
  const VoiceRecordStarted();
}

/// User released the mic button (PTT release) — audio bytes ready to send.
class VoiceRecordStopped extends CompanionEvent {
  const VoiceRecordStopped(this.audioBytes);
  final List<int> audioBytes;
  @override
  List<Object?> get props => [audioBytes];
}

/// Voice recording was cancelled (e.g. swipe-up gesture).
class VoiceRecordCancelled extends CompanionEvent {
  const VoiceRecordCancelled();
}
