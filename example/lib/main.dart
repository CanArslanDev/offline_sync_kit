import 'package:flutter/material.dart';
import 'package:offline_sync_kit/offline_sync_kit.dart';
import 'models/todo.dart';
import 'models/encryption_manager.dart';
import 'helpers/storage_helper.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize encryption manager
  await EncryptionManager().initialize();

  // Initialize sync manager
  await initSyncManager();

  runApp(const MyApp());
}

Future<void> initSyncManager() async {
  // Put your API address here in a real application
  const baseUrl = 'https://jsonplaceholder.typicode.com';

  // Create platform-independent storage service
  final storageService =
      await StorageHelper.createPlatformAwareStorageService();

  // Register model factory
  (storageService as StorageServiceImpl).registerModelDeserializer<Todo>(
    'todo',
    (json) => Todo.fromJson(json),
  );

  // Enhanced security and performance options with SyncOptions
  final syncOptions = SyncOptions(
    syncInterval: const Duration(minutes: 15),
    useDeltaSync: true, // Enable delta synchronization
    conflictStrategy: ConflictResolutionStrategy.lastUpdateWins,
    batchSize: 20, // Higher value for batch operations
    autoSync: true,
    bidirectionalSync: true,
  );

  // Get encryption status from the manager
  final encryptionManager = EncryptionManager();
  final isEncryptionEnabled = encryptionManager.isEncryptionEnabled;

  /*
  // --- WebSocket Configuration Example ---
  // This code is disabled by default. Uncomment to use WebSocket functionality.
  
  // Create a custom WebSocket configuration
  final webSocketConfig = WebSocketConfig(
    serverUrl: wsUrl,
    pingInterval: 45, // Custom ping interval (45 seconds)
    reconnectDelay: 3000, // Custom reconnect delay (3 seconds)
    maxReconnectAttempts: 5, // Custom max reconnect attempts
    
    // Custom messages
    connectionEstablishedMessage: 'Connected to server successfully',
    connectionClosedMessage: 'Disconnected from server',
    connectionFailedMessage: 'Failed to connect to server',
    reconnectingMessage: 'Attempting to reconnect',
    requestTimeoutMessage: 'Request to server timed out',

    // Custom ping message format
    pingMessageFormat: {'type': 'heartbeat', 'status': 'alive'},

    // Custom subscription message formatter
    subscriptionMessageFormatter: (channel, parameters) => {
      'action': 'join',
      'room': channel,
      'params': parameters,
      'client_info': {'app_version': '1.0.0'},
    },

    // Custom message types
    subscriptionMessageType: 'room_subscription',
    requestMessageType: 'api_request',
  );

  // Create a custom event mapper for WebSocket events
  final eventMapper = SyncEventMapper(
    // Custom WebSocket event name to SyncEventType mappings
    eventNameToTypeMap: {
      'item_updated': SyncEventType.modelUpdated,
      'item_created': SyncEventType.modelAdded,
      'item_removed': SyncEventType.modelDeleted,
      'sync_complete': SyncEventType.syncCompleted,
      'sync_begin': SyncEventType.syncStarted,
      'sync_failure': SyncEventType.syncError,
      'connection_opened': SyncEventType.connectionEstablished,
      'connection_closed': SyncEventType.connectionClosed,
      'connection_error': SyncEventType.connectionFailed,
      'connection_retry': SyncEventType.reconnecting,
      'data_conflict': SyncEventType.conflictDetected,
      'conflict_resolved': SyncEventType.conflictResolved,
    },
    // Custom SyncEventType to WebSocket event name mappings
    typeToEventNameMap: {
      SyncEventType.modelUpdated: 'item_updated',
      SyncEventType.modelAdded: 'item_created',
      SyncEventType.modelDeleted: 'item_removed',
      SyncEventType.syncCompleted: 'sync_complete',
      SyncEventType.syncStarted: 'sync_begin',
      SyncEventType.syncError: 'sync_failure',
      SyncEventType.connectionEstablished: 'connection_opened',
      SyncEventType.connectionClosed: 'connection_closed',
      SyncEventType.connectionFailed: 'connection_error',
      SyncEventType.reconnecting: 'connection_retry',
      SyncEventType.conflictDetected: 'data_conflict',
      SyncEventType.conflictResolved: 'conflict_resolved',
    },
  );

  // Create WebSocket network client with custom config and event mapper
  final webSocketClient = WebSocketNetworkClient.withConfig(
    config: webSocketConfig,
    eventMapper: eventMapper,
    requestTimeout: 20000, // 20 seconds timeout
  );

  // Listen to WebSocket events with custom event mapper
  webSocketClient.eventStream.listen((event) {
    // Get the custom event name from our mapper
    final customEventName = eventMapper.mapTypeToEventName(event.type);
    debugPrint('WebSocket event: $customEventName - ${event.message}');

    // Handle different event types
    switch (event.type) {
      case SyncEventType.modelUpdated:
        debugPrint('Model updated: ${event.data}');
        break;
      case SyncEventType.connectionEstablished:
        debugPrint('Connected to WebSocket server');
        break;
      case SyncEventType.connectionClosed:
        debugPrint('Disconnected from WebSocket server');
        break;
      default:
        break;
    }
  });
  
  // Connect to WebSocket server (would be managed by OfflineSyncManager in a real app)
  webSocketClient.connect().then((_) {
    // Subscribe to channels after connection
    webSocketClient.subscribe('todos');
    webSocketClient.subscribe('users');
  }).catchError((error) {
    debugPrint('Failed to connect to WebSocket server: $error');
  });
  
  // You can use the WebSocket client here if your sync manager supports it
  // networkClient: webSocketClient,
  */

  // Initialize sync manager with optional encryption
  await OfflineSyncManager.initialize(
    baseUrl: baseUrl,
    storageService: storageService,
    syncOptions: syncOptions,
    enableEncryption: isEncryptionEnabled, // Use value from EncryptionManager
    encryptionKey:
        isEncryptionEnabled
            ? 'secure-key-here'
            : null, // Only provide key if enabled
  );

  // Register Todo model with OfflineSyncManager
  OfflineSyncManager.instance.registerModelFactory<Todo>(
    'todo',
    (json) => Todo.fromJson(json),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Sync Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
