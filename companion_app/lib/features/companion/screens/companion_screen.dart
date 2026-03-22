import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/companion_bloc.dart';
import '../bloc/companion_event.dart';
import '../bloc/companion_state.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, required this.botId, required this.botName});

  final String botId;
  final String botName;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    context.read<CompanionBloc>().add(
          CompanionConnectRequested(botId: widget.botId),
        );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<CompanionBloc>().add(CompanionMessageSent(text));
    _inputCtrl.clear();
    setState(() => _isComposing = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.botName),
            BlocBuilder<CompanionBloc, CompanionState>(
              buildWhen: (prev, curr) =>
                  prev.connectionStatus != curr.connectionStatus,
              builder: (_, state) => Text(
                _connectionLabel(state.connectionStatus),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: _connectionColor(context, state.connectionStatus)),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _MessageList(scrollCtrl: _scrollCtrl)),
          _InputBar(
            controller: _inputCtrl,
            isComposing: _isComposing,
            onChanged: (v) => setState(() => _isComposing = v.trim().isNotEmpty),
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  String _connectionLabel(ConnectionStatus s) => switch (s) {
        ConnectionStatus.connected => '已连接',
        ConnectionStatus.reconnecting => '连接中…',
        ConnectionStatus.disconnected => '未连接',
      };

  Color _connectionColor(BuildContext ctx, ConnectionStatus s) =>
      switch (s) {
        ConnectionStatus.connected => Colors.green,
        ConnectionStatus.reconnecting => Colors.orange,
        ConnectionStatus.disconnected => Colors.red,
      };
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.scrollCtrl});
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CompanionBloc, CompanionState>(
      listenWhen: (prev, curr) => curr.messages.length != prev.messages.length,
      listener: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollCtrl.hasClients) {
            scrollCtrl.animateTo(
              scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      },
      buildWhen: (prev, curr) =>
          prev.messages != curr.messages || prev.errorMessage != curr.errorMessage,
      builder: (context, state) {
        if (state.messages.isEmpty) {
          return const Center(
            child: Text(
              '有什么想说的吗？',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          itemCount: state.messages.length +
              (state.errorMessage != null ? 1 : 0),
          itemBuilder: (_, i) {
            if (state.errorMessage != null && i == state.messages.length) {
              return MessageBubble(
                message: ChatMessage(
                  id: 'error',
                  role: MessageRole.assistant,
                  text: state.errorMessage!,
                  status: MessageStatus.error,
                  createdAt: DateTime.now(),
                ),
              );
            }
            return MessageBubble(message: state.messages[i]);
          },
        );
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isComposing,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isComposing;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: (_) => isComposing ? onSend() : null,
                maxLines: null,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: '说点什么…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedOpacity(
              opacity: isComposing ? 1 : 0.4,
              duration: const Duration(milliseconds: 150),
              child: IconButton.filled(
                onPressed: isComposing ? onSend : null,
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
