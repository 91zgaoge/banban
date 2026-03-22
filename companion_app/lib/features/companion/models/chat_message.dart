import 'package:equatable/equatable.dart';

enum MessageRole { user, assistant }

enum MessageStatus { complete, streaming, thinking, error }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.status,
    required this.createdAt,
    this.durationMs,
  });

  final String id;
  final MessageRole role;
  final String text;
  final MessageStatus status;
  final DateTime createdAt;
  final int? durationMs; // only for assistant final messages

  ChatMessage copyWith({
    String? text,
    MessageStatus? status,
    int? durationMs,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  List<Object?> get props => [id, role, text, status, createdAt, durationMs];
}
