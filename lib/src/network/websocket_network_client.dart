import 'dart:async';

import '../models/sync_event.dart';
import '../models/sync_event_mapper.dart';
import '../models/websocket_config.dart';
import 'network_client.dart';
import 'rest_request.dart';
import 'websocket_connection_manager.dart';

/// Network client that operates over WebSocket protocol.
///
/// This class implements the NetworkClient interface to provide data exchange
/// over WebSockets instead of HTTP. It enables real-time data synchronization.
class WebSocketNetworkClient implements NetworkClient {
  /// WebSocket connection manager
  final WebSocketConnectionManager _connectionManager;

  /// Request timeout in milliseconds
  final int _requestTimeout;

  /// Event mapper for converting between event names and types
  final SyncEventMapper _eventMapper;

  /// Pending responses for incomplete requests
  final Map<String, Completer<NetworkResponse>> _pendingRequests = {};

  /// Next request ID
  int _nextRequestId = 1;

  /// Event controller
  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Event stream
  Stream<SyncEvent> get eventStream => _eventController.stream;

  /// Combined event stream (both connection and data events)
  Stream<SyncEvent> get combinedEventStream {
    return Stream.multi((controller) {
      final subscription1 = _eventController.stream.listen(controller.add);
      final subscription2 = _connectionManager.eventStream.listen(
        controller.add,
      );

      controller.onCancel = () {
        subscription1.cancel();
        subscription2.cancel();
      };
    });
  }

  /// Creates a new WebSocketNetworkClient instance.
  ///
  /// [connectionManager] WebSocket connection manager.
  /// [requestTimeout] request timeout in milliseconds.
  /// [eventMapper] optional custom event mapper for WebSocket events.
  WebSocketNetworkClient({
    required WebSocketConnectionManager connectionManager,
    int requestTimeout = 30000, // 30 seconds
    SyncEventMapper? eventMapper,
  }) : _connectionManager = connectionManager,
       _requestTimeout = requestTimeout,
       _eventMapper = eventMapper ?? SyncEventMapper() {
    _setupEventListeners();
  }

  /// Creates a new WebSocketNetworkClient with a custom WebSocketConfig.
  ///
  /// [config] WebSocket configuration options.
  /// [eventMapper] optional custom event mapper for WebSocket events.
  factory WebSocketNetworkClient.withConfig({
    required WebSocketConfig config,
    SyncEventMapper? eventMapper,
    int requestTimeout = 30000,
  }) {
    return WebSocketNetworkClient(
      connectionManager: WebSocketConnectionManager.withConfig(config),
      requestTimeout: requestTimeout,
      eventMapper: eventMapper,
    );
  }

  /// Sets up event listeners.
  void _setupEventListeners() {
    _connectionManager.stateStream.listen((state) {
      if (state == WebSocketConnectionState.closed ||
          state == WebSocketConnectionState.error) {
        // Cancel all pending requests when connection is closed or error occurs
        _cancelAllPendingRequests('WebSocket connection closed');
      }
    });

    // Add message handler
    _connectionManager.addMessageHandler(_handleIncomingMessage);
  }

  /// Handles incoming WebSocket messages.
  void _handleIncomingMessage(Map<String, dynamic> message) {
    // Process response messages (custom format: request/response protocol)
    if (message.containsKey('requestId')) {
      final String requestId = message['requestId'];

      final completer = _pendingRequests[requestId];
      if (completer != null) {
        final bool isSuccess = message['status'] == 'success';
        final int statusCode = message['statusCode'] ?? (isSuccess ? 200 : 400);
        final data = message['data'];

        completer.complete(
          NetworkResponse(
            statusCode: statusCode,
            data: data,
            error: message['error'] ?? '',
            headers: Map<String, String>.from(message['headers'] ?? {}),
          ),
        );

        _pendingRequests.remove(requestId);
      }
    }
    // Process event messages
    else if (message.containsKey('event')) {
      final String event = message['event'];

      // Map the event name to SyncEventType using the event mapper
      final eventType = _eventMapper.mapEventNameToType(event);

      if (eventType != null) {
        _emitEvent(
          SyncEvent(
            type: eventType,
            message: message['message'] ?? '',
            data: message['data'],
          ),
        );
      }
    }
  }

  /// Emits an event.
  void _emitEvent(SyncEvent event) {
    _eventController.add(event);
  }

  /// Initiates a WebSocket connection.
  Future<void> connect() {
    return _connectionManager.connect();
  }

  /// Closes the WebSocket connection.
  Future<void> disconnect() {
    return _connectionManager.disconnect();
  }

  /// Subscribes to a WebSocket channel.
  ///
  /// [channel] name of the channel to subscribe to.
  /// [parameters] channel parameters (optional).
  Future<void> subscribe(String channel, {Map<String, dynamic>? parameters}) {
    return _connectionManager.subscribe(channel, parameters: parameters);
  }

  /// Unsubscribes from a WebSocket channel.
  ///
  /// [channel] name of the channel to unsubscribe from.
  Future<void> unsubscribe(String channel) {
    return _connectionManager.unsubscribe(channel);
  }

  /// Sends a request and waits for a response.
  ///
  /// [method] HTTP method ('GET', 'POST', etc.)
  /// [endpoint] request endpoint
  /// [body] request body (optional)
  /// [headers] request headers (optional)
  /// [queryParameters] query parameters (optional)
  Future<NetworkResponse> _sendRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (!_connectionManager.isConnected) {
      await connect();
    }

    final String requestId = (_nextRequestId++).toString();
    final completer = Completer<NetworkResponse>();
    _pendingRequests[requestId] = completer;

    // Prepare the request
    final Map<String, dynamic> request = {
      'requestId': requestId,
      'method': method,
      'endpoint': endpoint,
      if (body != null) 'body': body,
      if (headers != null) 'headers': headers,
      if (queryParameters != null) 'queryParameters': queryParameters,
    };

    // Set up request timeout
    final timer = Timer(Duration(milliseconds: _requestTimeout), () {
      if (!completer.isCompleted) {
        final WebSocketConfig config = _connectionManager.config;
        completer.complete(
          NetworkResponse(
            statusCode: 408, // Request Timeout
            error: config.requestTimeoutMessage,
          ),
        );
        _pendingRequests.remove(requestId);
      }
    });

    try {
      // Send the request
      await _connectionManager.send(
        request,
        eventType: _connectionManager.config.requestMessageType,
      );

      // Wait for response
      final response = await completer.future;
      timer.cancel();
      return response;
    } catch (e) {
      timer.cancel();
      _pendingRequests.remove(requestId);
      return NetworkResponse(
        statusCode: 500,
        error: '${_connectionManager.config.errorSendingRequestMessage}: $e',
      );
    }
  }

  /// Cancels all pending requests.
  void _cancelAllPendingRequests(String reason) {
    for (final requestId in _pendingRequests.keys) {
      final completer = _pendingRequests[requestId];
      if (completer != null && !completer.isCompleted) {
        completer.complete(NetworkResponse(statusCode: 0, error: reason));
      }
    }
    _pendingRequests.clear();
  }

  @override
  Future<NetworkResponse> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    RestRequest? requestConfig,
  }) {
    return _sendRequest(
      method: 'GET',
      endpoint: endpoint,
      headers: headers,
      queryParameters: queryParameters,
    );
  }

  @override
  Future<NetworkResponse> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) {
    return _sendRequest(
      method: 'POST',
      endpoint: endpoint,
      body: body,
      headers: headers,
    );
  }

  @override
  Future<NetworkResponse> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) {
    return _sendRequest(
      method: 'PUT',
      endpoint: endpoint,
      body: body,
      headers: headers,
    );
  }

  @override
  Future<NetworkResponse> delete(
    String endpoint, {
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) {
    return _sendRequest(method: 'DELETE', endpoint: endpoint, headers: headers);
  }

  /// Sends a PATCH request
  @override
  Future<NetworkResponse> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) {
    return _sendRequest(
      method: 'PATCH',
      endpoint: endpoint,
      body: body,
      headers: headers,
    );
  }

  /// Cleans up resources.
  void dispose() {
    _cancelAllPendingRequests(_connectionManager.config.clientClosedMessage);
    _connectionManager.removeMessageHandler(_handleIncomingMessage);
    _eventController.close();
  }
}
