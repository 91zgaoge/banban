import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/audio/recorder.dart';
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
  final _voiceRecorder = VoiceRecorder();
  bool _isComposing = false;
  bool _hasAudioPermission = false;

  @override
  void initState() {
    super.initState();
    context.read<CompanionBloc>().add(
          CompanionConnectRequested(botId: widget.botId),
        );
    _requestAudioPermission();
  }

  Future<void> _requestAudioPermission() async {
    final granted = await _voiceRecorder.requestPermission();
    if (mounted) setState(() => _hasAudioPermission = granted);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _voiceRecorder.dispose();
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

  Future<void> _onMicPressStart() async {
    if (!_hasAudioPermission) {
      final granted = await _voiceRecorder.requestPermission();
      if (!granted || !mounted) return;
      setState(() => _hasAudioPermission = true);
    }
    await _voiceRecorder.start();
    if (mounted) {
      context.read<CompanionBloc>().add(const VoiceRecordStarted());
    }
  }

  Future<void> _onMicPressEnd() async {
    final bytes = await _voiceRecorder.stop();
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      context.read<CompanionBloc>().add(VoiceRecordStopped(bytes));
    } else {
      context.read<CompanionBloc>().add(const VoiceRecordCancelled());
    }
  }

  Future<void> _onMicPressCancel() async {
    await _voiceRecorder.stop(); // discard bytes
    if (mounted) {
      context.read<CompanionBloc>().add(const VoiceRecordCancelled());
    }
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
          BlocBuilder<CompanionBloc, CompanionState>(
            buildWhen: (prev, curr) =>
                prev.isRecording != curr.isRecording ||
                prev.transcriptionText != curr.transcriptionText,
            builder: (context, state) {
              if (state.isRecording) {
                return const _RecordingIndicator();
              }
              if (state.transcriptionText != null) {
                return _TranscriptionPreview(text: state.transcriptionText!);
              }
              return const SizedBox.shrink();
            },
          ),
          _InputBar(
            controller: _inputCtrl,
            isComposing: _isComposing,
            onChanged: (v) => setState(() => _isComposing = v.trim().isNotEmpty),
            onSend: _sendMessage,
            onMicPressStart: _onMicPressStart,
            onMicPressEnd: _onMicPressEnd,
            onMicPressCancel: _onMicPressCancel,
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

// ---------------------------------------------------------------------------
// Message list
// ---------------------------------------------------------------------------

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
          itemCount: state.messages.length + (state.errorMessage != null ? 1 : 0),
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

// ---------------------------------------------------------------------------
// Recording indicator
// ---------------------------------------------------------------------------

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Text(
            '录音中… 松开发送',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.red),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transcription preview
// ---------------------------------------------------------------------------

class _TranscriptionPreview extends StatelessWidget {
  const _TranscriptionPreview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.transcribe, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isComposing,
    required this.onChanged,
    required this.onSend,
    required this.onMicPressStart,
    required this.onMicPressEnd,
    required this.onMicPressCancel,
  });

  final TextEditingController controller;
  final bool isComposing;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final Future<void> Function() onMicPressStart;
  final Future<void> Function() onMicPressEnd;
  final Future<void> Function() onMicPressCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocBuilder<CompanionBloc, CompanionState>(
      buildWhen: (prev, curr) => prev.isRecording != curr.isRecording,
      builder: (context, state) {
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
                // Mic button (PTT)
                GestureDetector(
                  onLongPressStart: (_) => onMicPressStart(),
                  onLongPressEnd: (_) => onMicPressEnd(),
                  onLongPressCancel: () => onMicPressCancel(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isRecording
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.transparent,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        state.isRecording ? Icons.mic : Icons.mic_none_rounded,
                        color: state.isRecording
                            ? Colors.red
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    onSubmitted: (_) => isComposing ? onSend() : null,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: state.isRecording ? '正在录音…' : '说点什么…',
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
      },
    );
  }
}
