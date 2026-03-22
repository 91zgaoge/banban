import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'streaming_text.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = _isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = _isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    final alignment =
        _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    Widget content;
    switch (message.status) {
      case MessageStatus.thinking:
        content = _ThinkingDots(color: textColor);
      case MessageStatus.streaming:
        content = StreamingText(
          text: message.text,
          style: TextStyle(color: textColor, fontSize: 15),
        );
      case MessageStatus.complete:
        content = Text(
          message.text,
          style: TextStyle(color: textColor, fontSize: 15),
        );
      case MessageStatus.error:
        content = Text(
          '⚠️ ${message.text}',
          style: TextStyle(color: colorScheme.error, fontSize: 14),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(_isUser ? 16 : 4),
                bottomRight: Radius.circular(_isUser ? 4 : 16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: content,
          ),
          if (message.status == MessageStatus.complete &&
              message.durationMs != null &&
              message.role == MessageRole.assistant)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                _formatDuration(message.durationMs!),
                style: TextStyle(
                  color: colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    final secs = (ms / 1000).toStringAsFixed(1);
    return '${secs}s';
  }
}

/// Animated three-dot thinking indicator.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.color});
  final Color color;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _dot = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _dot = (_dot + 1) % 3);
          _ctrl.reset();
          _ctrl.forward();
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = List.generate(3, (i) {
      return AnimatedOpacity(
        opacity: i == _dot ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}
