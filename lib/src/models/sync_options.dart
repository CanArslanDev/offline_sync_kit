import 'package:equatable/equatable.dart';
import 'connectivity_options.dart';
import 'conflict_resolution_strategy.dart';
import '../enums/sync_strategy.dart';

/// Configuration options for synchronization behavior
class SyncOptions extends Equatable {
  /// The interval between automatic synchronization attempts
  final Duration syncInterval;

  /// The maximum number of retry attempts for failed synchronization
  final int maxRetryAttempts;

  /// Whether synchronization should be performed automatically
  final bool autoSync;

  /// Whether to sync both from client to server and server to client
  final bool bidirectionalSync;

  /// Network connectivity requirements for synchronization
  final ConnectivityOptions connectivityRequirement;

  /// Number of items to process in a single batch
  final int batchSize;

  /// Factor by which to increase delay between retry attempts
  final Duration retryBackoffFactor;

  /// Initial delay before the first retry attempt
  final Duration initialBackoffDelay;

  /// Maximum delay between retry attempts
  final Duration maxBackoffDelay;

  /// Whether to use delta synchronization (only sync changed fields)
  final bool useDeltaSync;

  /// Strategy to use when resolving conflicts
  final ConflictResolutionStrategy conflictStrategy;

  /// Custom conflict resolver for advanced conflict resolution
  final ConflictResolver? conflictResolver;

  /// Strategy to use when fetching data
  final FetchStrategy fetchStrategy;

  /// Strategy to use when deleting data
  final DeleteStrategy deleteStrategy;

  /// Strategy to use when saving data (insert/update)
  final SaveStrategy saveStrategy;

  /// Creates a new set of synchronization options
  const SyncOptions({
    this.syncInterval = const Duration(minutes: 15),
    this.maxRetryAttempts = 5,
    this.autoSync = true,
    this.bidirectionalSync = true,
    this.connectivityRequirement = ConnectivityOptions.any,
    this.batchSize = 10,
    this.retryBackoffFactor = const Duration(seconds: 2),
    this.initialBackoffDelay = const Duration(seconds: 1),
    this.maxBackoffDelay = const Duration(minutes: 5),
    this.useDeltaSync = false,
    this.conflictStrategy = ConflictResolutionStrategy.lastUpdateWins,
    this.conflictResolver,
    this.fetchStrategy = FetchStrategy.backgroundSync,
    this.deleteStrategy = DeleteStrategy.optimisticDelete,
    this.saveStrategy = SaveStrategy.optimisticSave,
  });

  /// Creates a copy of these options with the given fields replaced with new values
  SyncOptions copyWith({
    Duration? syncInterval,
    int? maxRetryAttempts,
    bool? autoSync,
    bool? bidirectionalSync,
    ConnectivityOptions? connectivityRequirement,
    int? batchSize,
    Duration? retryBackoffFactor,
    Duration? initialBackoffDelay,
    Duration? maxBackoffDelay,
    bool? useDeltaSync,
    ConflictResolutionStrategy? conflictStrategy,
    ConflictResolver? conflictResolver,
    FetchStrategy? fetchStrategy,
    DeleteStrategy? deleteStrategy,
    SaveStrategy? saveStrategy,
  }) {
    return SyncOptions(
      syncInterval: syncInterval ?? this.syncInterval,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      autoSync: autoSync ?? this.autoSync,
      bidirectionalSync: bidirectionalSync ?? this.bidirectionalSync,
      connectivityRequirement:
          connectivityRequirement ?? this.connectivityRequirement,
      batchSize: batchSize ?? this.batchSize,
      retryBackoffFactor: retryBackoffFactor ?? this.retryBackoffFactor,
      initialBackoffDelay: initialBackoffDelay ?? this.initialBackoffDelay,
      maxBackoffDelay: maxBackoffDelay ?? this.maxBackoffDelay,
      useDeltaSync: useDeltaSync ?? this.useDeltaSync,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      conflictResolver: conflictResolver ?? this.conflictResolver,
      fetchStrategy: fetchStrategy ?? this.fetchStrategy,
      deleteStrategy: deleteStrategy ?? this.deleteStrategy,
      saveStrategy: saveStrategy ?? this.saveStrategy,
    );
  }

  @override
  List<Object?> get props => [
    syncInterval,
    maxRetryAttempts,
    autoSync,
    bidirectionalSync,
    connectivityRequirement,
    batchSize,
    retryBackoffFactor,
    initialBackoffDelay,
    maxBackoffDelay,
    useDeltaSync,
    conflictStrategy,
    conflictResolver,
    fetchStrategy,
    deleteStrategy,
    saveStrategy,
  ];

  /// The interval in seconds for periodic synchronization
  int get syncIntervalSeconds => syncInterval.inSeconds;

  /// Whether periodic synchronization is enabled
  bool get periodicSyncEnabled => autoSync && syncInterval.inSeconds > 0;

  /// Whether to synchronize when connectivity is restored
  bool get syncOnConnect => autoSync;

  /// Creates a conflict resolution handler based on these options
  ConflictResolutionHandler createConflictHandler() {
    return ConflictResolutionHandler(
      strategy: conflictStrategy,
      customResolver: conflictResolver,
    );
  }
}

/// Network connectivity requirements for sync operations
enum ConnectivityRequirement {
  /// Sync can be performed on any available network connection
  any,

  /// Sync should only be performed on WiFi connections
  wifi,

  /// Sync should only be performed on unmetered connections (no data charges)
  unmetered,
}
