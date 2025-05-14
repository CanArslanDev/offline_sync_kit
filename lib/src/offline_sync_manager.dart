import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

import 'models/sync_model.dart';
import 'models/sync_options.dart';
import 'models/sync_result.dart';
import 'models/sync_status.dart';
import 'network/default_network_client.dart';
import 'network/network_client.dart';
import 'network/rest_request.dart';
import 'repositories/sync_repository.dart';
import 'repositories/sync_repository_impl.dart';
import 'services/connectivity_service.dart';
import 'services/storage_service.dart';
import 'sync_engine.dart';
import 'query/query.dart';
import 'enums/sync_strategy.dart';

/// Function type for creating model instances from JSON
///
/// This typedef is used to register factory functions that can create model
/// instances from JSON data retrieved from the server or local storage.
typedef ModelFactory<T extends SyncModel> =
    T Function(Map<String, dynamic> json);

/// Main entry point for the offline synchronization framework
///
/// This class serves as the primary interface for applications to interact with
/// the offline synchronization system. It manages model registration, storage,
/// and synchronization with a remote API.
///
/// Usage:
/// ```dart
/// // Initialize the manager
/// await OfflineSyncManager.initialize(
///   baseUrl: 'https://api.example.com',
///   storageService: MyStorageService(),
/// );
///
/// // Register model factories
/// OfflineSyncManager.instance.registerModelFactory<Todo>(
///   'todo',
///   (json) => Todo.fromJson(json),
/// );
///
/// // Save and sync models
/// final todo = Todo(title: 'New task');
/// await OfflineSyncManager.instance.saveModel(todo);
/// ```
class OfflineSyncManager {
  /// Singleton instance of the OfflineSyncManager
  static OfflineSyncManager? _instance;

  /// The sync engine that performs the actual synchronization operations
  final SyncEngine _syncEngine;

  /// Map of model type names to factory functions for model creation
  final Map<String, ModelFactory> _modelFactories = {};

  /// Service for storing and retrieving data locally
  final StorageService _storageService;

  /// Service for monitoring network connectivity
  final ConnectivityService _connectivityService;

  /// Subscription to the connectivity service's connection stream
  late StreamSubscription<bool> _connectivitySubscription;

  /// Enables encryption for synced data
  ///
  /// When enabled, models will be encrypted before sending to the server and
  /// decrypted after retrieval. This adds security but reduces server-side
  /// searchability.
  ///
  /// [encryptionKey] A secure key used for encryption/decryption
  /// [ivLength] Initialization vector length (16 bytes recommended)
  void enableEncryption(String encryptionKey, {int ivLength = 16}) {
    final keyBytes = sha256.convert(utf8.encode(encryptionKey)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV.fromLength(ivLength);
    _encrypter = encrypt.Encrypter(encrypt.AES(key));
    _encryptionIV = iv;
    _encryptionEnabled = true;
  }

  /// Disables encryption for synced data
  void disableEncryption() {
    _encryptionEnabled = false;
    _encrypter = null;
    _encryptionIV = null;
  }

  /// Encrypts data before sending to server (if encryption is enabled)
  ///
  /// This is used internally by the sync system to encrypt data when
  /// encryption is enabled.
  ///
  /// [data] The data to encrypt
  /// Returns the encrypted data or original data if encryption is disabled
  Map<String, dynamic> _encryptDataIfEnabled(Map<String, dynamic> data) {
    if (!_encryptionEnabled || _encrypter == null) {
      return data;
    }

    // Don't encrypt the ID field so the server can still identify records
    final id = data['id'];
    final modelType = data['modelType'];

    // Encrypt the entire data object
    final dataJson = jsonEncode(data);
    final encrypted = _encrypter!.encrypt(dataJson, iv: _encryptionIV!);

    // Return a map with the ID and the encrypted data
    return {
      'id': id,
      'modelType': modelType,
      'encrypted': true,
      'data': encrypted.base64,
    };
  }

  /// Decrypts data received from server (if encryption is enabled)
  ///
  /// This is used internally by the sync system to decrypt data when
  /// encryption is enabled.
  ///
  /// [data] The data to decrypt
  /// Returns the decrypted data or original data if encryption is disabled
  Map<String, dynamic> _decryptDataIfNeeded(Map<String, dynamic> data) {
    if (!_encryptionEnabled || _encrypter == null) {
      return data;
    }

    // Skip decryption if not encrypted
    if (data['encrypted'] != true || data['data'] == null) {
      return data;
    }

    try {
      // Decrypt the data field
      final encryptedData = encrypt.Encrypted.fromBase64(data['data']);
      final decryptedJson = _encrypter!.decrypt(
        encryptedData,
        iv: _encryptionIV!,
      );

      // Parse the decrypted JSON
      return jsonDecode(decryptedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error decrypting data: $e');
      // Return the original data if decryption fails
      return data;
    }
  }

  // Add encryption-related properties
  bool _encryptionEnabled = false;
  encrypt.Encrypter? _encrypter;
  encrypt.IV? _encryptionIV;

  /// Private constructor, use [initialize] instead
  ///
  /// This constructor is private to enforce the singleton pattern.
  /// Applications should use the [initialize] method to create and access
  /// the OfflineSyncManager.
  OfflineSyncManager._({
    required SyncEngine syncEngine,
    required StorageService storageService,
    required ConnectivityService connectivityService,
  }) : _syncEngine = syncEngine,
       _storageService = storageService,
       _connectivityService = connectivityService {
    _setupConnectivityListener();
  }

  /// Sets up a listener for connectivity changes
  ///
  /// When connectivity is restored, automatically attempt to sync pending changes.
  /// This ensures that data is synchronized as soon as a connection becomes available.
  void _setupConnectivityListener() {
    _connectivitySubscription = _connectivityService.connectionStream.listen((
      isConnected,
    ) {
      if (isConnected) {
        _syncEngine.syncAllPending();
      }
    });
  }

  /// Initializes the offline sync manager singleton
  ///
  /// This must be called before accessing the [instance].
  ///
  /// Parameters:
  /// - [baseUrl]: The base URL for the remote API
  /// - [networkClient]: Optional custom network client implementation
  /// - [connectivityService]: Optional custom connectivity service implementation
  /// - [storageService]: Required storage service implementation
  /// - [syncOptions]: Optional configuration options for synchronization
  /// - [enableEncryption]: Whether to enable encryption for data
  /// - [encryptionKey]: Key to use for encryption if enabled
  /// - [customRepository]: Optional custom repository implementation. If provided,
  ///   this will be used instead of creating a new SyncRepositoryImpl.
  ///
  /// Returns the initialized singleton instance
  ///
  /// Throws an [UnimplementedError] if no storage service is provided
  static Future<OfflineSyncManager> initialize({
    required String baseUrl,
    NetworkClient? networkClient,
    ConnectivityService? connectivityService,
    StorageService? storageService,
    SyncOptions? syncOptions,
    bool enableEncryption = false,
    String? encryptionKey,
    SyncRepository? customRepository,
  }) async {
    // Return existing instance if already initialized
    if (_instance != null) {
      return _instance!;
    }

    // Use provided options or create default options
    final options = syncOptions ?? const SyncOptions();

    // Use provided connectivity service or create default implementation
    final connectivity = connectivityService ?? ConnectivityServiceImpl();

    // Use provided network client or create default implementation
    final defaultNetworkClient =
        networkClient ?? DefaultNetworkClient(baseUrl: baseUrl);

    // Validate storage service
    StorageService storage;
    if (storageService != null) {
      storage = storageService;
    } else {
      throw UnimplementedError(
        'Storage service must be provided. Implement a concrete class for StorageService.',
      );
    }

    // Use custom repository if provided, otherwise create default implementation
    final syncRepository =
        customRepository ??
        SyncRepositoryImpl(
          networkClient: defaultNetworkClient,
          storageService: storage,
        );

    final syncEngine = SyncEngine(
      repository: syncRepository,
      storageService: storage,
      connectivityService: connectivity,
      options: options,
    );

    // Create and store singleton instance
    _instance = OfflineSyncManager._(
      syncEngine: syncEngine,
      storageService: storage,
      connectivityService: connectivity,
    );

    // Set up encryption if enabled
    if (enableEncryption && encryptionKey != null) {
      _instance!.enableEncryption(encryptionKey);

      // If using the default network client, set up its encryption handlers
      if (defaultNetworkClient is DefaultNetworkClient) {
        defaultNetworkClient.setEncryptionHandler(
          _instance!._encryptDataIfEnabled,
        );
        defaultNetworkClient.setDecryptionHandler(
          _instance!._decryptDataIfNeeded,
        );
      }
    }

    return _instance!;
  }

  /// Accesses the singleton instance of the offline sync manager
  ///
  /// Throws a [StateError] if [initialize] has not been called
  static OfflineSyncManager get instance {
    if (_instance == null) {
      throw StateError(
        'OfflineSyncManager not initialized. Call initialize() first.',
      );
    }
    return _instance!;
  }

  /// Registers a factory function for creating model instances of type [T]
  ///
  /// Parameters:
  /// - [modelType]: The unique identifier for this model type
  /// - [factory]: A function that creates model instances from JSON data
  ///
  /// This must be called for each model type before using other operations.
  /// The factory function is used to deserialize JSON data into model objects
  /// when retrieving data from local storage or the server.
  void registerModelFactory<T extends SyncModel>(
    String modelType,
    ModelFactory<T> factory,
  ) {
    _modelFactories[modelType] = factory;
    _syncEngine.registerModelType(modelType);
  }

  /// Saves a model to local storage and synchronizes it with the server if needed
  ///
  /// Parameters:
  /// - [model]: The model instance to save
  ///
  /// If the model is not already synced, it will be synchronized automatically.
  /// This method ensures that the model is both saved locally and sent to the server.
  Future<void> saveModel<T extends SyncModel>(T model) async {
    // First save the model to local storage
    await _storageService.save<T>(model);

    // Only trigger synchronization if the model is not already synced
    if (!model.isSynced) {
      // Wait for synchronization to complete
      // If encryption is enabled, the data will be encrypted before sending
      await _syncEngine.syncItem<T>(model);
      // Mark the model as synced to prevent future sync attempts
      await _storageService.markAsSynced<T>(model.id, model.modelType);
    }
  }

  /// Saves multiple models to local storage and synchronizes unsynced models
  ///
  /// Parameters:
  /// - [models]: The list of model instances to save
  ///
  /// Only models that are not already synced will be synchronized.
  /// This method is more efficient than calling [saveModel] multiple times.
  Future<void> saveModels<T extends SyncModel>(List<T> models) async {
    if (models.isEmpty) {
      return;
    }

    // First save all models to local storage
    await _storageService.saveAll<T>(models);

    // Filter out models that are already synced
    final unsyncedModels = models.where((model) => !model.isSynced).toList();

    // Only attempt synchronization if there are unsynced models
    if (unsyncedModels.isNotEmpty) {
      await _syncEngine.syncAll<T>(unsyncedModels);
    }
  }

  /// Updates a model in local storage and marks it for sync
  ///
  /// This method:
  /// 1. Saves the updated model to local storage
  /// 2. Marks the model as not synced (if it wasn't already)
  /// 3. Returns the updated model instance from storage
  ///
  /// @param model The model to update
  /// @return A Future containing the updated model
  Future<T> updateModel<T extends SyncModel>(T model) async {
    // Mark as not synced if it was previously synced
    final modelToSave =
        model.isSynced ? model.copyWith(isSynced: false) as T : model;

    await _storageService.save<T>(modelToSave);
    await _syncEngine.updateSyncStatus();

    return modelToSave;
  }

  /// Updates specific fields of a model for delta synchronization
  ///
  /// This method:
  /// 1. Gets the existing model from storage
  /// 2. Updates only the specified fields
  /// 3. Tracks which fields were changed
  /// 4. Saves the updated model to storage
  /// 5. Marks the model as not synced
  ///
  /// @param modelType The type of model to update
  /// @param id The ID of the model to update
  /// @param changes Map of field names to new values
  /// @return A Future containing the updated model
  Future<T?> updateModelFields<T extends SyncModel>(
    String modelType,
    String id,
    Map<String, dynamic> changes,
  ) async {
    final existingModel = await getModel<T>(modelType, id);

    if (existingModel == null) {
      return null;
    }

    // Create a model factory for this type
    final factory = _modelFactories[modelType];
    if (factory == null) {
      throw Exception('No model factory registered for $modelType');
    }

    // Convert existing model to JSON
    final modelJson = existingModel.toJson();

    // Apply changes
    modelJson.addAll(changes);

    // Create updated model with tracked changed fields
    final Set<String> changedFields = {
      ...(existingModel.changedFields),
      ...changes.keys,
    };
    modelJson['changedFields'] = changedFields.toList();

    // Create new model instance
    final updatedModel = factory(modelJson) as T;

    // Save with isSynced = false
    final modelToSave = updatedModel.copyWith(isSynced: false) as T;
    await _storageService.save<T>(modelToSave);
    await _syncEngine.updateSyncStatus();

    return modelToSave;
  }

  /// Synchronizes a specific model instance using delta synchronization
  ///
  /// This method will only send changed fields to the server instead of the entire model.
  /// If the model has no changed fields, it will be skipped.
  /// If encryption is enabled, the data will be encrypted before sending to the server.
  ///
  /// @param model The model to sync with the server
  /// @param options Optional synchronization options
  /// @return A Future containing the sync result
  Future<SyncResult> syncItemDelta<T extends SyncModel>(
    T model, {
    SyncOptions? options,
  }) async {
    if (!model.hasChanges) {
      // Skip if no fields have changed
      return SyncResult.success(processedItems: 0);
    }

    // If encryption is enabled, the data will be encrypted in the network client
    return _syncEngine.syncItemDelta<T>(model, options: options);
  }

  /// Deletes a model from local storage
  ///
  /// Parameters:
  /// - [id]: The unique identifier of the model to delete
  /// - [modelType]: The type of the model to delete
  ///
  /// Note: This method only deletes the model locally. If you need to delete it
  /// on the server as well, you should implement that logic separately.
  Future<void> deleteModel<T extends SyncModel>(
    String id,
    String modelType,
  ) async {
    await _storageService.delete<T>(id, modelType);
  }

  /// Retrieves a single model from local storage by ID
  ///
  /// Parameters:
  /// - [id]: The unique identifier of the model to retrieve
  /// - [modelType]: The type of the model to retrieve
  ///
  /// Returns the model instance if found, null otherwise
  Future<T?> getModel<T extends SyncModel>(String id, String modelType) async {
    return _storageService.get<T>(id, modelType);
  }

  /// Retrieves all models of a specific type from local storage
  ///
  /// Parameters:
  /// - [modelType]: The type of models to retrieve
  ///
  /// Returns a list of all models of the specified type
  Future<List<T>> getAllModels<T extends SyncModel>(String modelType) async {
    return _storageService.getAll<T>(modelType);
  }

  /// Retrieves models of a specific type from local storage using a structured query
  ///
  /// This method provides a more powerful way to filter and sort models using
  /// the Query class which supports where conditions, ordering, and pagination.
  ///
  /// Parameters:
  /// - [modelType]: The type of models to retrieve
  /// - [query]: Optional structured query to filter the models
  ///
  /// Returns a list of models matching the query
  Future<List<T>> getModelsWithQuery<T extends SyncModel>(
    String modelType, {
    Query? query,
    bool forceLocalSyncFromRemote = false,
    FetchStrategy? policy,
    RestRequest? restConfig,
  }) async {
    if (forceLocalSyncFromRemote) {
      // If force sync is requested, fetch from remote first
      try {
        // Convert Query to a map manually if needed
        Map<String, dynamic>? queryParams;
        if (query != null) {
          // Create a simplified conversion from Query to Map
          queryParams = {};

          // Add where conditions if available
          if (query.where != null && query.where!.isNotEmpty) {
            // Just add basic key-value pairs from conditions
            // This is simplified and might need to be expanded based on your query structure
            for (var condition in query.where!) {
              if (condition.field != null && condition.value != null) {
                queryParams[condition.field!] = condition.value;
              }
            }
          }

          // Add other query parameters
          if (query.orderBy != null) queryParams['orderBy'] = query.orderBy;
          if (query.descending != null)
            queryParams['descending'] = query.descending;
          if (query.limit != null) queryParams['limit'] = query.limit;
          if (query.offset != null) queryParams['offset'] = query.offset;
        }

        final result = await _syncEngine.fetchItems<T>(
          modelType,
          query: queryParams,
          forceRefresh: true,
          modelFetchStrategy: policy,
          restConfig: restConfig,
        );

        if (result.isSuccessful && result.data != null) {
          return result.data!;
        }
      } catch (e) {
        debugPrint('Error fetching from remote: $e');
        // Continue to fetch from local if remote fails
      }
    }

    return _storageService.getItemsWithQuery<T>(modelType, query: query);
  }

  /// Synchronizes all pending models with the server
  ///
  /// Returns a [SyncResult] containing the outcome of the synchronization
  ///
  /// This method attempts to synchronize all pending changes across all registered
  /// model types with the server. It's useful for ensuring that all local changes
  /// are reflected on the server.
  Future<SyncResult> syncAll() async {
    return _syncEngine.syncAllPending();
  }

  /// Synchronizes all models of a specific type with the server
  ///
  /// Parameters:
  /// - [modelType]: The type of models to synchronize
  ///
  /// Returns a [SyncResult] containing the outcome of the synchronization
  ///
  /// This method is useful when you want to sync only a specific type of model,
  /// rather than all pending changes.
  Future<SyncResult> syncByModelType(String modelType) async {
    return _syncEngine.syncByModelType(modelType);
  }

  /// Synchronizes a single model with the server
  ///
  /// Parameters:
  /// - [model]: The model instance to synchronize
  ///
  /// Returns a [SyncResult] containing the outcome of the synchronization
  ///
  /// This method is useful when you want to sync a specific model immediately,
  /// regardless of its current sync status.
  Future<SyncResult> syncItem<T extends SyncModel>(T model) async {
    return _syncEngine.syncItem<T>(model);
  }

  /// Fetches items of type [T] from the server
  ///
  /// This method retrieves items from the remote API and optionally
  /// saves them to local storage.
  ///
  /// [modelType] The type of model to fetch
  /// [since] Optional timestamp to only fetch items modified since this time
  /// [limit] Optional maximum number of items to fetch
  /// [offset] Optional offset for pagination
  /// [saveToStorage] Whether to save fetched items to local storage
  /// Returns a list of model instances
  Future<List<T>> fetchItems<T extends SyncModel>(
    String modelType, {
    DateTime? since,
    int? limit,
    int? offset,
    bool saveToStorage = true,
  }) async {
    if (!_modelFactories.containsKey(modelType)) {
      throw Exception('No model factory registered for $modelType');
    }

    // Convert _modelFactories to the format expected by SyncRepositoryImpl
    final Map<String, dynamic Function(Map<String, dynamic>)> factoriesMap = {};
    _modelFactories.forEach((key, value) {
      factoriesMap[key] = (json) => value(json);
    });

    // Get the repository from _syncEngine
    final repository = _syncEngine.repository;
    if (repository is! SyncRepositoryImpl) {
      throw Exception('Repository is not of type SyncRepositoryImpl');
    }

    // Fetch items from server
    final items = await repository.fetchItems<T>(
      modelType,
      since: since,
      limit: limit,
      offset: offset,
      modelFactories: factoriesMap,
    );

    // Save to storage if requested
    if (saveToStorage && items.isNotEmpty) {
      await _storageService.saveAll<T>(items);
    }

    return items;
  }

  /// Pulls and synchronizes data from the server for a specific model type
  ///
  /// This method is used for bidirectional synchronization to get the latest
  /// data from the server and update the local storage accordingly.
  ///
  /// [modelType] The type of model to synchronize
  /// [lastSyncTime] Optional timestamp to only fetch items changed since this time
  /// Returns a SyncResult with details of the operation
  Future<SyncResult> pullFromServer<T extends SyncModel>(
    String modelType, {
    DateTime? lastSyncTime,
  }) async {
    if (!_modelFactories.containsKey(modelType)) {
      throw Exception('No model factory registered for $modelType');
    }

    // Convert _modelFactories to the format expected by SyncRepositoryImpl
    final Map<String, dynamic Function(Map<String, dynamic>)> factoriesMap = {};
    _modelFactories.forEach((key, value) {
      factoriesMap[key] = (json) => value(json);
    });

    // Get the repository from _syncEngine
    final repository = _syncEngine.repository;
    if (repository is! SyncRepositoryImpl) {
      throw Exception('Repository is not of type SyncRepositoryImpl');
    }

    try {
      // First update the repository's fetchItems method with our model factories
      // Then call pullFromServer which will use fetchItems internally
      final result = await repository.pullFromServer<T>(
        modelType,
        lastSyncTime ?? await _storageService.getLastSyncTime(),
        modelFactories: factoriesMap,
      );

      if (result.isSuccessful) {
        await _storageService.setLastSyncTime(DateTime.now());
      }

      await _syncEngine.updateSyncStatus();
      return result;
    } catch (e) {
      debugPrint('Error pulling from server for $modelType: $e');
      return SyncResult.failed(error: e.toString());
    }
  }

  /// A stream of synchronization status updates
  ///
  /// Listen to this stream to be notified of changes in the synchronization status.
  /// This is useful for updating UI components that need to reflect the current
  /// synchronization state.
  Stream<SyncStatus> get syncStatusStream => _syncEngine.statusStream;

  /// The current synchronization status
  ///
  /// Returns a [SyncStatus] object containing the current status
  ///
  /// Use this method to get a snapshot of the current synchronization state,
  /// including whether the device is connected, if a sync is in progress,
  /// and how many changes are pending.
  Future<SyncStatus> get currentStatus => _syncEngine.getCurrentStatus();

  /// Starts periodic synchronization of models
  ///
  /// Synchronization will be performed according to the [SyncOptions]
  /// provided during initialization.
  ///
  /// This is useful for ensuring data is regularly synchronized without
  /// manual intervention.
  Future<void> startPeriodicSync() async {
    await _syncEngine.startPeriodicSync();
  }

  /// Stops periodic synchronization
  ///
  /// Call this method when you want to stop automatic synchronization,
  /// for example, to conserve battery or when the app goes into the background.
  Future<void> stopPeriodicSync() async {
    await _syncEngine.stopPeriodicSync();
  }

  /// Disposes resources used by the offline sync manager
  ///
  /// This should be called when the application is terminated to avoid memory leaks.
  void dispose() {
    _connectivitySubscription.cancel();
    _syncEngine.dispose();
  }
}
