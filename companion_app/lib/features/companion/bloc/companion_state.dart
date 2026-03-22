import 'package:equatable/equatable.dart';

import '../models/chat_message.dart';

enum ConnectionStatus { disconnected, connected, reconnecting }

class CompanionState extends Equatable {
  const CompanionState({
    this.messages = const [],
    this.connectionStatus = ConnectionStatus.disconnected,
    this.isAssistantTyping = false,
    this.isRecording = false,
    this.isTtsPlaying = false,
    this.transcriptionText,
    this.botId,
    this.errorMessage,
  });

  final List<ChatMessage> messages;
  final ConnectionStatus connectionStatus;
  final bool isAssistantTyping;

  /// True while the microphone is actively recording.
  final bool isRecording;

  /// True while TTS audio is playing back.
  final bool isTtsPlaying;

  /// Live transcription text echoed from the server (shown while waiting for reply).
  final String? transcriptionText;

  final String? botId;
  final String? errorMessage;

  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  CompanionState copyWith({
    List<ChatMessage>? messages,
    ConnectionStatus? connectionStatus,
    bool? isAssistantTyping,
    bool? isRecording,
    bool? isTtsPlaying,
    String? transcriptionText,
    String? botId,
    String? errorMessage,
    bool clearError = false,
    bool clearTranscription = false,
  }) {
    return CompanionState(
      messages: messages ?? this.messages,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      isAssistantTyping: isAssistantTyping ?? this.isAssistantTyping,
      isRecording: isRecording ?? this.isRecording,
      isTtsPlaying: isTtsPlaying ?? this.isTtsPlaying,
      transcriptionText: clearTranscription ? null : (transcriptionText ?? this.transcriptionText),
      botId: botId ?? this.botId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        messages,
        connectionStatus,
        isAssistantTyping,
        isRecording,
        isTtsPlaying,
        transcriptionText,
        botId,
        errorMessage,
      ];
}
