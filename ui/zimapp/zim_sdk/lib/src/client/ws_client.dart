import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// WebSocket push types from server
enum WsPushType {
  newMessage(2001),
  kickedOffline(2002),
  tokenExpired(2003),
  unknown(0);

  final int code;
  const WsPushType(this.code);

  static WsPushType fromCode(int code) {
    return WsPushType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => WsPushType.unknown,
    );
  }
}

class ZimWsClient {
  static final ZimWsClient _instance = ZimWsClient._internal();
  factory ZimWsClient() => _instance;
  ZimWsClient._internal();

  WebSocketChannel? _channel;
  String? _wsUrl;
  String? _token;
  String? _userID;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Request-response matching
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};
  int _msgIncr = 0;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectDelayMs = 1000;
  static const int _maxReconnectDelayMs = 30000;
  static const int _heartbeatIntervalSec = 25;

  void init({
    required String wsUrl,
    required String token,
    required String userID,
  }) {
    _wsUrl = wsUrl;
    _token = token;
    _userID = userID;
  }

  Future<void> connect() async {
    if (_wsUrl == null || _token == null || _userID == null) {
      throw StateError('WS client not initialized');
    }
    if (_isConnected) return;

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl!),
        headers: {'token': _token},
        pingInterval: const Duration(seconds: 20),
      );
      _isConnected = true;
      _reconnectDelayMs = 1000;
      _shouldReconnect = true;

      // Send login message via legacy protocol
      _sendLogin();

      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Start heartbeat
      _startHeartbeat();
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
      rethrow;
    }
  }

  void _sendLogin() {
    _send({
      'reqFuncName': 'Login',
      'userID': _userID,
      'token': _token,
    });
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Check for request-response matching
      final msgIncr = data['msgIncr'] as String?;
      if (msgIncr != null && msgIncr.isNotEmpty && _pendingRequests.containsKey(msgIncr)) {
        final completer = _pendingRequests.remove(msgIncr)!;
        final errCode = data['errCode'] as int? ?? 0;
        if (errCode != 0) {
          completer.completeError(
            Exception('WS error: ${data['errMsg']} (code: $errCode)'),
          );
        } else {
          completer.complete(data);
        }
        return;
      }

      _messageController.add(data);
    } catch (e) {
      // Ignore parse errors
    }
  }

  void _onError(dynamic error) {
    _isConnected = false;
    _stopHeartbeat();
    _failPendingRequests(error);
    _scheduleReconnect();
  }

  void _onDone() {
    _isConnected = false;
    _stopHeartbeat();
    _failPendingRequests(Exception('WebSocket closed'));
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectDelayMs), () {
      _reconnectTimer = null;
      _reconnectDelayMs = min(_reconnectDelayMs * 2, _maxReconnectDelayMs);
      connect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSec),
      (_) {
        if (_isConnected) {
          _send({'reqFuncName': 'SyncMsg'});
        }
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _failPendingRequests(dynamic error) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingRequests.clear();
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// Send message via WebSocket legacy protocol with request-response matching
  Future<Map<String, dynamic>> sendMessage({
    required String sendID,
    required String recvID,
    required String content,
    int sessionType = 1,
    int contentType = 101,
    String? groupID,
    String? clientMsgID,
  }) async {
    final incr = '${_msgIncr++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[incr] = completer;

    final payload = {
      'reqFuncName': 'SendMsg',
      'msgIncr': incr,
      'data': {
        'sendID': sendID,
        'recvID': recvID,
        if (groupID != null) 'groupID': groupID,
        'content': content,
        'sessionType': sessionType,
        'contentType': contentType,
        if (clientMsgID != null) 'clientMsgID': clientMsgID,
      },
    };
    _send(payload);

    // Timeout after 10 seconds
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingRequests.remove(incr);
        throw TimeoutException('WS sendMessage timeout');
      },
    );
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _failPendingRequests(Exception('WebSocket disconnected'));
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }

  bool get isConnected => _isConnected;
}
