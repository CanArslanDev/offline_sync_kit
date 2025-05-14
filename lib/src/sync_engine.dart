import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'enums/sync_strategy.dart';
import 'models/sync_model.dart';
import 'models/sync_options.dart';
import 'models/sync_result.dart';
import 'models/sync_status.dart';
import 'query/query.dart';
import 'query/where_condition.dart';
import 'repositories/sync_repository.dart';
import 'services/connectivity_service.dart';
import 'services/storage_service.dart';
import 'network/rest_request.dart';

/// Core engine for handling the synchronization of models between local storage and remote server
///
/// The SyncEngine coordinates all synchronization operations, manages model types,
/// handles network connectivity, and maintains synchronization state.
class SyncEngine {
  /// Repository for handling data synchronization with the server
  final SyncRepository _repository;

  /// Service for local data storage operations
  final StorageService _storageService;

  /// Service for monitoring network connectivity
  final ConnectivityService _connectivityService;

  /// Configuration options for synchronization behavior
  final SyncOptions _options;

  /// Stream controller for broadcasting synchronization status updates
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  /// Timer for periodic synchronization if enabled
  Timer? _syncTimer;

  /// Flag to prevent multiple synchronization operations running simultaneously
  bool _isSyncing = false;

  /// List of registered model types that can be synchronized
  final List<String> _registeredModelTypes = [];

  /// Timestamp of the last successful synchronization
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Number of changes pending synchronization
  int _pendingCount = 0;

  /// Creates a new SyncEngine instance
  ///
  /// Parameters:
  /// - [repository]: Repository for handling data synchronization
  /// - [storageService]: Service for local data storage
  /// - [connectivityService]: Service for monitoring network connectivity
  /// - [options]: Configuration options for synchronization
  SyncEngine({
    required SyncRepository repository,
    required StorageService storageService,
    required ConnectivityService connectivityService,
    SyncOptions? options,
  }) : _repository = repository,
       _storageService = storageService,
       _connectivityService = connectivityService,
       _options = options ?? const SyncOptions() {
    _initialize();
  }

  /// Initializes the sync engine, storage service, and connectivity monitoring
  ///
  /// This method sets up listeners for connectivity changes and configures
  /// periodic synchronization if enabled in the options
  Future<void> _initialize() async {
    await _storageService.initialize();
    _lastSyncTime = await _storageService.getLastSyncTime();
    _pendingCount = await _storageService.getPendingCount();

    _updateStatus();

    _connectivityService.connectionStream.listen((isConnected) {
      _updateStatus(isConnected: isConnected);

      if (isConnected &&
          _options.autoSync &&
          _pendingCount > 0 &&
          !_isSyncing) {
        _triggerSync();
      }
    });

    if (_options.autoSync && _options.syncInterval.inSeconds > 0) {
      await startPeriodicSync();
    }
  }

  /// Stream of synchronization status updates
  ///
  /// Listen to this stream to be notified of changes in the synchronization status
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Get the repository for accessing server data
  ///
  /// This is primarily used for advanced operations like fetching data directly from the server
  SyncRepository get repository => _repository;

  /// Gets the current synchronization status
  ///
  /// Returns a [SyncStatus] object containing the current status
  Future<SyncStatus> getCurrentStatus() async {
    final isConnected = await _connectivityService.isConnected;
    return SyncStatus(
      isConnected: isConnected,
      isSyncing: _isSyncing,
      pendingChanges: _pendingCount,
      lastSyncTime: _lastSyncTime,
    );
  }

  /// Registers a model type for synchronization
  ///
  /// Every model type that needs synchronization must be registered
  /// before any synchronization operations can be performed on it
  ///
  /// Parameters:
  /// - [modelType]: The unique identifier for the model type to register
  void registerModelType(String modelType) {
    if (!_registeredModelTypes.contains(modelType)) {
      _registeredModelTypes.add(modelType);
    }
  }

  /// Synchronizes a single model with the server
  ///
  /// This method will send the model to the server and update its sync status.
  /// If the device is offline, the model will be saved locally for later synchronization.
  ///
  /// Parameters:
  /// - [item]: The model to synchronize
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult<void>> syncItem<T extends SyncModel>(T item) async {
    registerModelType(item.modelType);

    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    if (!isConnected) {
      await _storageService.save(item);
      await _updatePendingCount();
      return SyncResult<void>(
        status: SyncResultStatus.connectionError,
        errorMessages: ['No internet connection available'],
        source: ResultSource.offlineCache,
      );
    }

    _setIsSyncing(true);

    try {
      // Apply save strategy - use model-specific strategy if available, otherwise use global
      final saveStrategy = item.saveStrategy ?? _options.saveStrategy;

      if (saveStrategy == SaveStrategy.optimisticSave) {
        // Save locally first
        await _storageService.save(item);
      }

      final result = await _repository.syncItem(item);

      // For waitForRemote strategy, save locally after remote success
      if (saveStrategy == SaveStrategy.waitForRemote && result.isSuccessful) {
        await _storageService.save(item);
      }

      await _updateLastSyncTime();
      await _updatePendingCount();
      _setIsSyncing(false);

      // Convert non-generic result to generic
      return SyncResult<void>(
        status: result.status,
        processedItems: result.processedItems,
        failedItems: result.failedItems,
        errorMessages: result.errorMessages,
        timeTaken: result.timeTaken,
      );
    } catch (e) {
      _setIsSyncing(false);
      return SyncResult<void>(
        status: SyncResultStatus.failed,
        errorMessages: [e.toString()],
      );
    }
  }

  /// Synchronizes multiple models with the server
  ///
  /// This method will send all the provided models to the server and update their sync status.
  /// If the device is offline, the models will be saved locally for later synchronization.
  ///
  /// Parameters:
  /// - [items]: The list of models to synchronize
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult> syncAll<T extends SyncModel>(List<T> items) async {
    if (items.isEmpty) {
      return SyncResult.noChanges();
    }

    registerModelType(items.first.modelType);

    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    if (!isConnected) {
      await _storageService.saveAll(items);
      await _updatePendingCount();
      return SyncResult.connectionError();
    }

    _setIsSyncing(true);

    try {
      final result = await _repository.syncAll(
        items,
        bidirectional: _options.bidirectionalSync,
      );

      await _updateLastSyncTime();
      await _updatePendingCount();
      _setIsSyncing(false);
      return result;
    } catch (e) {
      _setIsSyncing(false);
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Synchronizes all pending (unsynced) models of all registered types
  ///
  /// This method finds all models that haven't been synchronized yet across all
  /// registered model types and attempts to sync them with the server.
  ///
  /// Returns a [SyncResult] with combined results of all synchronization operations
  Future<SyncResult> syncAllPending() async {
    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    if (!isConnected) {
      return SyncResult.connectionError();
    }

    if (_isSyncing) {
      return SyncResult.failed(error: 'Sync already in progress');
    }

    _setIsSyncing(true);

    try {
      SyncResult finalResult = SyncResult.noChanges();

      for (final modelType in _registeredModelTypes) {
        final result = await syncByModelType(modelType);

        if (result.status == SyncResultStatus.failed ||
            result.status == SyncResultStatus.partial) {
          finalResult = result;
        } else if (finalResult.status == SyncResultStatus.noChanges &&
            result.status == SyncResultStatus.success) {
          finalResult = result;
        }
      }

      await _updateLastSyncTime();
      await _updatePendingCount();
      _setIsSyncing(false);
      return finalResult;
    } catch (e) {
      _setIsSyncing(false);
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Synchronizes all models of a specific type
  ///
  /// This method finds all models of the specified type that haven't been
  /// synchronized yet and attempts to sync them with the server.
  ///
  /// Parameters:
  /// - [modelType]: The type of models to synchronize
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult> syncByModelType(String modelType) async {
    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    if (!isConnected) {
      return SyncResult.connectionError();
    }

    final wasAlreadySyncing = _isSyncing;
    if (!wasAlreadySyncing) {
      if (_isSyncing) {
        return SyncResult.failed(error: 'Sync already in progress');
      }
      _setIsSyncing(true);
    }

    try {
      final items = await _storageService.getPending(modelType);

      if (items.isEmpty) {
        if (!wasAlreadySyncing) {
          _setIsSyncing(false);
        }
        return SyncResult.noChanges();
      }

      final result = await _repository.syncAll(
        items,
        bidirectional: _options.bidirectionalSync,
      );

      if (!wasAlreadySyncing) {
        await _updateLastSyncTime();
        await _updatePendingCount();
        _setIsSyncing(false);
      }

      return result;
    } catch (e) {
      if (!wasAlreadySyncing) {
        _setIsSyncing(false);
      }
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Fetches models from the server and saves them to local storage
  ///
  /// This method performs a pull operation to retrieve data from the server
  /// and update the local storage with the latest changes.
  ///
  /// Parameters:
  /// - [modelType]: The type of models to fetch
  /// - [since]: Optional timestamp to fetch only models updated since that time
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult> pullFromServer<T extends SyncModel>(
    String modelType, {
    DateTime? since,
    Map<String, dynamic Function(Map<String, dynamic>)>? modelFactories,
  }) async {
    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    if (!isConnected) {
      return SyncResult.connectionError();
    }

    _setIsSyncing(true);

    try {
      final result = await _repository.pullFromServer<T>(
        modelType,
        since ?? _lastSyncTime,
        modelFactories: modelFactories,
      );

      await _updateLastSyncTime();
      _setIsSyncing(false);
      return result;
    } catch (e) {
      _setIsSyncing(false);
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Starts a timer for periodic synchronization
  ///
  /// The sync interval is determined by the options provided in the constructor.
  /// If periodic sync is already running, the previous timer is cancelled.
  ///
  /// Returns a Future that completes when the timer is set up
  Future<void> startPeriodicSync() async {
    stopPeriodicSync();

    if (_options.syncInterval.inSeconds > 0) {
      _syncTimer = Timer.periodic(_options.syncInterval, (_) => _triggerSync());
    }
  }

  /// Stops the periodic synchronization timer
  ///
  /// If no periodic sync is running, this method has no effect.
  ///
  /// Returns a Future that completes when the timer is cancelled
  Future<void> stopPeriodicSync() async {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Triggers synchronization of pending changes
  ///
  /// This method is called by the periodic timer or when connectivity is restored.
  /// It checks for pending changes and initiates synchronization if needed.
  Future<void> _triggerSync() async {
    if (!_isSyncing && _pendingCount > 0) {
      final isConnected = await _connectivityService.isConnectionSatisfied(
        _options.connectivityRequirement,
      );

      if (isConnected) {
        await syncAllPending();
      }
    }
  }

  /// Updates the last sync time in memory and persists it
  ///
  /// This is a helper method to DRY up code and ensure consistency
  Future<void> _updateLastSyncTime() async {
    _lastSyncTime = DateTime.now();
    await _storageService.setLastSyncTime(_lastSyncTime);
  }

  /// Updates the pending changes count
  ///
  /// This is a helper method to DRY up code and ensure consistency
  Future<void> _updatePendingCount() async {
    _pendingCount = await _storageService.getPendingCount();
    _updateStatus();
  }

  /// Sets the syncing state and updates the status
  ///
  /// Parameters:
  /// - [value]: New value for the _isSyncing flag
  void _setIsSyncing(bool value) {
    _isSyncing = value;
    _updateStatus();
  }

  /// Updates the synchronization status and broadcasts it to listeners
  ///
  /// Parameters:
  /// - [isConnected]: Optional parameter to specify the connection state.
  ///   If not provided, the current connection state will be retrieved.
  void _updateStatus({bool? isConnected}) async {
    final connected = isConnected ?? await _connectivityService.isConnected;

    _statusController.add(
      SyncStatus(
        isConnected: connected,
        isSyncing: _isSyncing,
        pendingChanges: _pendingCount,
        lastSyncTime: _lastSyncTime,
      ),
    );
  }

  /// Releases resources and cleans up
  ///
  /// This method should be called when the application is shutting down
  /// or when the sync engine is no longer needed.
  void dispose() {
    _syncTimer?.cancel();
    _statusController.close();
  }

  /// Synchronizes a specific model instance using delta synchronization
  ///
  /// This method will only send changed fields to the server instead of the entire model.
  /// If the model has no changed fields, it will be skipped.
  /// If encryption is enabled, the data will be encrypted before sending to the server.
  ///
  /// @param model The model to sync with the server
  /// @param options Optional synchronization options to override the defaults
  /// @return A Future containing the sync result
  Future<SyncResult> syncItemDelta<T extends SyncModel>(
    T item, {
    SyncOptions? options,
  }) async {
    registerModelType(item.modelType);

    final effectiveOptions = options ?? _options;
    final isConnected = await _connectivityService.isConnectionSatisfied(
      effectiveOptions.connectivityRequirement,
    );

    if (!isConnected) {
      await _storageService.save(item);
      await _updatePendingCount();
      return SyncResult.connectionError();
    }

    if (item.changedFields.isEmpty) {
      return SyncResult.success(processedItems: 0);
    }

    _setIsSyncing(true);

    try {
      // Extract only the changed fields from the model
      final changedFields = item.toJsonDelta();

      // Try to use syncDelta if the repository implements it
      SyncResult result;
      try {
        result = await _repository.syncDelta(item, changedFields);
      } catch (e) {
        // Fallback to updateItem if syncDelta is not fully implemented
        final updatedItem = await _repository.updateItem(item);

        if (updatedItem != null) {
          // Success - save and mark as synced
          await _storageService.save(updatedItem);
          result = SyncResult.success(processedItems: 1);
        } else {
          // Failed to update
          result = SyncResult.failed(
            error: 'Delta sync failed for ${item.modelType} with id ${item.id}',
          );
        }
      }

      await _updateLastSyncTime();
      await _updatePendingCount();
      _setIsSyncing(false);
      return result;
    } catch (e) {
      _setIsSyncing(false);
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Updates the sync status after operations
  ///
  /// This method checks the current pending count and updates the status
  Future<void> updateSyncStatus() async {
    await _updatePendingCount();
    _updateStatus();
  }

  /// Fetches items from the remote provider and syncs them to local storage
  ///
  /// Parameters:
  /// - [modelType]: The model type to fetch
  /// - [query]: Optional query parameters to filter the items
  /// - [forceRefresh]: Whether to force a refresh from the remote provider
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult<List<T>>> fetchItems<T extends SyncModel>(
    String modelType, {
    Map<String, dynamic>? query,
    bool forceRefresh = false,
    FetchStrategy? modelFetchStrategy,
    RestRequest? restConfig,
  }) async {
    registerModelType(modelType);

    // Use model-specific strategy if provided in parameter, otherwise use global
    final fetchStrategy = modelFetchStrategy ?? _options.fetchStrategy;

    // Get local items first unless remoteFirst strategy is used
    List<T>? localItems;
    if (fetchStrategy != FetchStrategy.remoteFirst) {
      // Convert Map<String, dynamic> query to Query object if necessary
      if (query != null) {
        // Simple conversion for basic queries
        final structuredQuery = _mapToQuery(query);
        localItems = await _storageService.getItemsWithQuery<T>(
          modelType,
          query: structuredQuery,
        );
      } else {
        localItems = await _storageService.getItemsWithQuery<T>(modelType);
      }
    }

    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    // Return local items only if offline or strategy is localOnly
    if (!isConnected || fetchStrategy == FetchStrategy.localOnly) {
      return SyncResult<List<T>>(
        status: SyncResultStatus.success,
        data: localItems ?? <T>[],
        source: isConnected ? ResultSource.local : ResultSource.offlineCache,
      );
    }

    // If using localWithRemoteFallback and we have local items, return them and sync in background
    if (fetchStrategy == FetchStrategy.localWithRemoteFallback &&
        localItems != null &&
        localItems.isNotEmpty) {
      // Start background sync if needed
      _fetchFromRemoteAndSync(modelType, query, localItems, fetchStrategy);
      return SyncResult<List<T>>(
        status: SyncResultStatus.success,
        data: localItems,
        source: ResultSource.local,
      );
    }

    // Otherwise fetch from remote
    _setIsSyncing(true);
    try {
      final result = await _repository.getItems<T>(
        modelType,
        query: query,
        requestConfig: restConfig,
      );

      if (result.isSuccessful) {
        // Only save remote items if not using remoteFirst or we got some items
        if (fetchStrategy != FetchStrategy.remoteFirst ||
            (result.data != null && result.data!.isNotEmpty)) {
          await _storageService.saveAll(result.data!);
        }

        await _updateLastSyncTime();
      }

      _setIsSyncing(false);
      return result;
    } catch (e) {
      _setIsSyncing(false);

      // If remote fails and we have local items, return those
      if (localItems != null) {
        return SyncResult<List<T>>(
          status: SyncResultStatus.success,
          data: localItems,
          source: ResultSource.offlineCache,
        );
      }

      return SyncResult<List<T>>(
        status: SyncResultStatus.failed,
        errorMessages: [e.toString()],
      );
    }
  }

  /// Helper method to convert a Map query to a structured Query object
  Query? _mapToQuery(Map<String, dynamic>? mapQuery) {
    if (mapQuery == null || mapQuery.isEmpty) {
      return null;
    }

    // Very basic conversion - this could be enhanced based on your query format
    List<WhereCondition> whereConditions = [];

    mapQuery.forEach((key, value) {
      // Skip special query parameters like orderBy, limit, etc.
      if (!['orderBy', 'descending', 'limit', 'offset'].contains(key)) {
        // Create an exact match condition
        whereConditions.add(WhereCondition.exact(key, value));
      }
    });

    String? orderBy = mapQuery['orderBy'] as String?;
    bool descending = mapQuery['descending'] as bool? ?? false;
    int? limit = mapQuery['limit'] as int?;
    int? offset = mapQuery['offset'] as int?;

    return Query(
      where: whereConditions.isEmpty ? null : whereConditions,
      orderBy: orderBy,
      descending: descending,
      limit: limit,
      offset: offset,
    );
  }

  /// Helper method to fetch items in the background and sync them
  Future<void> _fetchFromRemoteAndSync<T extends SyncModel>(
    String modelType,
    Map<String, dynamic>? query,
    List<T> existingItems,
    FetchStrategy fetchStrategy,
  ) async {
    if (fetchStrategy == FetchStrategy.backgroundSync) {
      // Only perform in background if strategy is backgroundSync
      _repository
          .getItems<T>(modelType, query: query)
          .then((result) {
            if (result.isSuccessful && result.data != null) {
              _storageService.saveAll(result.data!);
              _updateLastSyncTime();
            }
          })
          .catchError((_) {
            // Ignore errors in background sync
          });
    }
  }

  /// Deletes a model from local storage and remote provider
  ///
  /// Parameters:
  /// - [item]: The model to delete
  ///
  /// Returns a [SyncResult] with details of the operation
  Future<SyncResult<void>> deleteItem<T extends SyncModel>(T item) async {
    registerModelType(item.modelType);

    final isConnected = await _connectivityService.isConnectionSatisfied(
      _options.connectivityRequirement,
    );

    // Apply delete strategy - use model-specific strategy if available, otherwise use global
    final deleteStrategy = item.deleteStrategy ?? _options.deleteStrategy;

    if (deleteStrategy == DeleteStrategy.optimisticDelete) {
      // Delete locally first
      await _storageService.deleteModel(item);
    }

    if (!isConnected) {
      // Mark for deletion when we're back online
      final markedItem = item.markForDeletion();
      await _storageService.save(markedItem);
      await _updatePendingCount();
      return SyncResult<void>(
        status: SyncResultStatus.connectionError,
        errorMessages: ['No internet connection available'],
        source: ResultSource.offlineCache,
      );
    }

    _setIsSyncing(true);

    try {
      final success = await _repository.deleteItem(item);
      final result =
          success
              ? SyncResult<void>(status: SyncResultStatus.success)
              : SyncResult<void>(
                status: SyncResultStatus.failed,
                errorMessages: ['Failed to delete on server'],
              );

      // For waitForRemote strategy, delete locally after remote success
      if (deleteStrategy == DeleteStrategy.waitForRemote && success) {
        await _storageService.deleteModel(item);
      }

      await _updateLastSyncTime();
      await _updatePendingCount();
      _setIsSyncing(false);
      return result;
    } catch (e) {
      _setIsSyncing(false);

      // If remote delete fails with optimisticDelete strategy, mark for deletion to try again later
      if (deleteStrategy == DeleteStrategy.optimisticDelete) {
        final markedItem = item.markForDeletion();
        await _storageService.save(markedItem);
      }

      return SyncResult<void>(
        status: SyncResultStatus.failed,
        errorMessages: [e.toString()],
      );
    }
  }
}
