import 'package:equatable/equatable.dart';

import '../models/chat_message.dart';

enum ConnectionStatus { disconnected, connected, reconnecting }

class CompanionState extends Equatable {
  const CompanionState({
    this.messages = const [],
    this.connectionStatus = ConnectionStatus.disconnected,
    this.isAssistantTyping = false,
    this.botId,
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final ConnectionStatus connectionStatus;
  final bool isAssistantTyping;
  final String? botId;
  final String? errorMessage;

  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  CompanionState copyWith({
    List<ChatMessage>? messages,
    ConnectionStatus? connectionStatus,
    bool? isAssistantTyping,
    String? botId,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CompanionState(
      messages: messages ?? this.messages,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      isAssistantTyping: isAssistantTyping ?? this.isAssistantTyping,
      botId: botId ?? this.botId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        messages,
        connectionStatus,
        isAssistantTyping,
        botId,
        errorMessage,
      ];
}
