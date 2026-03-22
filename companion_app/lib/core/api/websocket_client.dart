import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

/// Events received from the server.
sealed class WsEvent {}

class WsStatusEvent extends WsEvent {
  WsStatusEvent(this.status);
  final String status; // e.g. "thinking"
}

class WsDeltaEvent extends WsEvent {
  WsDeltaEvent(this.text);
  final String text;
}

class WsFinalEvent extends WsEvent {
  WsFinalEvent({required this.text, required this.durationMs});
  final String text;
  final int durationMs;
}

class WsErrorEvent extends WsEvent {
  WsErrorEvent(this.message);
  final String message;
}

class WsPongEvent extends WsEvent {}

class WsConnectedEvent extends WsEvent {}

class WsDisconnectedEvent extends WsEvent {
  WsDisconnectedEvent({this.willReconnect = true});
  final bool willReconnect;
}

/// Manages a single WebSocket connection to the companion backend.
///
/// Reconnects automatically with exponential back-off (1s → max 30s).
///
/// Usage:
///   final client = CompanionWebSocketClient(url: url);
///   client.events.listen((event) { ... });
///   client.connect();
///   client.sendText("hello");
///   client.dispose();
class CompanionWebSocketClient {
  CompanionWebSocketClient({required this.wsUrl});

  final String wsUrl;

  final _controller = StreamController<WsEvent>.broadcast();
  Stream<WsEvent> get events => _controller.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _disposed = false;
  int _reconnectAttempt = 0;
  bool _intentionalClose = false;

  /// Connect (or reconnect) to the WebSocket.
  void connect() {
    if (_disposed) return;
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    _cleanup();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _controller.add(WsConnectedEvent());
      _reconnectAttempt = 0;
      _startPing();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> frame;
    try {
      frame = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = frame['type'] as String?;
    switch (type) {
      case 'status':
        _controller.add(WsStatusEvent(frame['status'] as String? ?? ''));
      case 'delta':
        _controller.add(WsDeltaEvent(frame['text'] as String? ?? ''));
      case 'final':
        _controller.add(WsFinalEvent(
          text: frame['text'] as String? ?? '',
          durationMs: (frame['duration_ms'] as num?)?.toInt() ?? 0,
        ));
      case 'error':
        _controller.add(WsErrorEvent(frame['message'] as String? ?? 'unknown error'));
      case 'pong':
        _controller.add(WsPongEvent());
      default:
        break;
    }
  }

  void _onError(Object error) {
    if (!_intentionalClose) _scheduleReconnect();
  }

  void _onDone() {
    if (!_intentionalClose) {
      _controller.add(WsDisconnectedEvent(willReconnect: true));
      _scheduleReconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      sendPing();
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionalClose) return;
    _reconnectTimer?.cancel();
    final delay = Duration(
      milliseconds: math.min(1000 * math.pow(2, _reconnectAttempt).toInt(), 30000),
    );
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  /// Send a text message to the companion.
  void sendText(String text) {
    _send({'type': 'input_text', 'text': text});
  }

  /// Send a ping frame.
  void sendPing() {
    _send({'type': 'ping'});
  }

  /// Send an abort request (cancel in-flight generation).
  void sendAbort() {
    _send({'type': 'abort'});
  }

  void _send(Map<String, dynamic> frame) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(json.encode(frame));
    } catch (_) {
      // Channel might be closed; reconnect will happen via onDone/onError
    }
  }

  /// Permanently close the connection.
  void dispose() {
    _disposed = true;
    _intentionalClose = true;
    _cleanup();
    _controller.close();
  }
}
