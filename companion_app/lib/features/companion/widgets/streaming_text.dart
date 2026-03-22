import 'package:flutter/material.dart';

/// Renders text that visually "arrives" character-by-character.
///
/// When [text] grows (delta arrives), the new characters fade in from 0→1
/// opacity over [charDuration]. Already-visible characters are stable.
class StreamingText extends StatefulWidget {
  const StreamingText({
    super.key,
    required this.text,
    this.style,
    this.charDuration = const Duration(milliseconds: 40),
  });

  final String text;
  final TextStyle? style;
  final Duration charDuration;

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with TickerProviderStateMixin {
  // Track how many characters were already visible before last update.
  int _prevLength = 0;
  String _prevText = '';

  // Per-character animation controllers for newly arrived chars.
  final List<AnimationController> _controllers = [];

  @override
  void didUpdateWidget(StreamingText old) {
    super.didUpdateWidget(old);
    if (widget.text != _prevText) {
      _onTextChanged();
    }
  }

  void _onTextChanged() {
    final newText = widget.text;
    if (newText.length <= _prevLength) {
      // Text was reset or truncated — clear animations.
      _disposeControllers();
      _prevLength = newText.length;
      _prevText = newText;
      return;
    }

    final newChars = newText.length - _prevLength;
    for (int i = 0; i < newChars; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: widget.charDuration,
      )..forward();
      _controllers.add(ctrl);
    }

    _prevLength = newText.length;
    _prevText = newText;
  }

  void _disposeControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (_controllers.isEmpty || _controllers.length < text.length) {
      // Fast path when all characters are stable.
      return Text(text, style: widget.style);
    }

    // Build a RichText with each "new" character fading in.
    final stableCount = text.length - _controllers.length;
    final spans = <InlineSpan>[];

    if (stableCount > 0) {
      spans.add(TextSpan(text: text.substring(0, stableCount)));
    }

    for (int i = 0; i < _controllers.length && stableCount + i < text.length; i++) {
      final char = text[stableCount + i];
      final anim = CurvedAnimation(
        parent: _controllers[i],
        curve: Curves.easeIn,
      );
      spans.add(
        WidgetSpan(
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Opacity(
              opacity: anim.value,
              child: Text(char, style: widget.style),
            ),
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(style: widget.style, children: spans),
    );
  }
}
