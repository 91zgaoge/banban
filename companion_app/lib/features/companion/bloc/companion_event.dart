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
