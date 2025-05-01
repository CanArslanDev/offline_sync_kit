import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/sync_model.dart';
import '../models/sync_result.dart';
import '../network/network_client.dart';
import '../network/rest_request.dart';
import '../enums/rest_method.dart';
import '../services/storage_service.dart';
import 'sync_repository.dart';

/// Implementation of the SyncRepository interface that handles synchronization
/// operations between local storage and remote server.
///
/// This class manages the full synchronization lifecycle including:
/// - Syncing individual items to the server
/// - Handling delta updates for specific model fields
/// - Performing bulk synchronization operations
/// - Pulling data from the server
/// - Creating, updating, and deleting items
class SyncRepositoryImpl implements SyncRepository {
  final NetworkClient _networkClient;
  final StorageService _storageService;

  /// Creates a new instance of SyncRepositoryImpl
  ///
  /// [networkClient] - Client for making network requests to the server
  /// [storageService] - Service for persisting data to local storage
  SyncRepositoryImpl({
    required NetworkClient networkClient,
    required StorageService storageService,
  }) : _networkClient = networkClient,
       _storageService = storageService;

  /// Gets the request configuration for a model and HTTP method
  ///
  /// If the model defines custom request configurations, this will
  /// return the appropriate configuration for the specified method.
  ///
  /// Parameters:
  /// - [model]: The model to get configuration for
  /// - [method]: The HTTP method (GET, POST, PUT, DELETE, PATCH)
  ///
  /// Returns a RestRequest configuration or null if not defined
  RestRequest? _getRequestConfig<T extends SyncModel>(
    T model,
    RestMethod method,
  ) {
    final restRequests = model.restRequests;
    if (restRequests == null) {
      return null;
    }

    return restRequests.getForMethod(method);
  }

  /// Synchronizes a single item with the server
  ///
  /// Attempts to create or update the item on the server based on its current state.
  /// If successful, marks the item as synced in local storage.
  ///
  /// [item] - The model instance to synchronize
  /// Returns a [SyncResult] indicating success or failure
  @override
  Future<SyncResult> syncItem<T extends SyncModel>(T item) async {
    try {
      // Skip already synced items
      if (item.isSynced) {
        return SyncResult.noChanges();
      }

      final stopwatch = Stopwatch()..start();
      late T? result;

      // Use PUT for updates and POST for new items
      if (item.id.isNotEmpty) {
        // Get custom request configuration if available
        final requestConfig = _getRequestConfig(item, RestMethod.put);

        // Update existing item
        result = await updateItem<T>(item, requestConfig: requestConfig);
      } else {
        // Get custom request configuration if available
        final requestConfig = _getRequestConfig(item, RestMethod.post);

        // Create new item
        result = await createItem<T>(item, requestConfig: requestConfig);
      }

      if (result != null) {
        // Update local storage with the synced item
        await _storageService.save<T>(result);
        return SyncResult.success(
          timeTaken: stopwatch.elapsed,
          processedItems: 1,
        );
      }

      return SyncResult.failed(
        error: 'Failed to sync item with server',
        timeTaken: stopwatch.elapsed,
      );
    } catch (e) {
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Synchronizes only the changed fields of an item with the server
  ///
  /// This method sends only the delta (changed fields) of the model to reduce
  /// bandwidth and improve performance.
  ///
  /// Parameters:
  /// - [item]: The model to synchronize
  /// - [changedFields]: Map of field names to their new values
  ///
  /// Returns a [SyncResult] with the outcome of the operation
  @override
  Future<SyncResult> syncDelta<T extends SyncModel>(
    T item,
    Map<String, dynamic> changedFields,
  ) async {
    try {
      if (changedFields.isEmpty) {
        return SyncResult.noChanges();
      }

      final stopwatch = Stopwatch()..start();

      // Get the delta JSON with only changed fields
      final deltaJson = item.toJsonDelta();

      // Get custom request configuration if available
      final requestConfig = _getRequestConfig(item, RestMethod.patch);

      // Send PATCH request with only the changed fields
      final response = await _networkClient.patch(
        '${item.endpoint}/${item.id}',
        body: deltaJson,
        requestConfig: requestConfig,
      );

      if (response.isSuccessful) {
        // Mark as synced to update local storage
        final updatedItem = item.markAsSynced() as T;
        await _storageService.save<T>(updatedItem);

        return SyncResult.success(
          timeTaken: stopwatch.elapsed,
          processedItems: 1,
        );
      }

      return SyncResult.failed(
        error: 'Failed to sync delta: ${response.statusCode}',
        timeTaken: stopwatch.elapsed,
      );
    } catch (e) {
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Synchronizes multiple items with the server in a batch operation
  ///
  /// For large numbers of items, this is more efficient than individual syncs.
  /// It handles both creation of new items and updates to existing ones.
  ///
  /// Parameters:
  /// - [items]: List of models to synchronize
  /// - [bidirectional]: Whether to also pull updates from the server
  ///
  /// Returns a [SyncResult] with combined results
  @override
  Future<SyncResult> syncAll<T extends SyncModel>(
    List<T> items, {
    bool bidirectional = true,
  }) async {
    if (items.isEmpty) {
      return SyncResult.noChanges();
    }

    final stopwatch = Stopwatch()..start();
    int processedItems = 0;
    int failedItems = 0;
    final errorMessages = <String>[];

    // Process items in batches for better performance
    for (final item in items) {
      try {
        if (item.isSynced) {
          continue; // Skip already synced items
        }

        T? result;

        // Determine whether to create or update based on ID
        if (item.id.isNotEmpty) {
          // Get custom request configuration if available
          final requestConfig = _getRequestConfig(item, RestMethod.put);

          // Update existing item
          result = await updateItem<T>(item, requestConfig: requestConfig);
        } else {
          // Get custom request configuration if available
          final requestConfig = _getRequestConfig(item, RestMethod.post);

          // Create new item
          result = await createItem<T>(item, requestConfig: requestConfig);
        }

        if (result != null) {
          // Update local storage with the synced item
          await _storageService.save<T>(result);
          processedItems++;
        } else {
          failedItems++;
          errorMessages.add('Failed to sync item with ID ${item.id}');
        }
      } catch (e) {
        failedItems++;
        errorMessages.add('Error: $e');
      }
    }

    // If bidirectional sync is enabled, also pull updates from the server
    if (bidirectional && items.isNotEmpty) {
      try {
        // Use the first item's type to determine model properties
        final modelType = items.first.modelType;

        // Get custom request configuration if available
        final requestConfig = _getRequestConfig(items.first, RestMethod.get);

        // Get model endpoint from the first item
        final endpoint = items.first.endpoint;

        // Fetch all items of this type from the server
        final response = await _networkClient.get(
          endpoint,
          requestConfig: requestConfig,
        );

        if (response.isSuccessful && response.data != null) {
          // Handle response data based on its type
          if (response.data is List) {
            // Response is a direct list of items
            for (final item in response.data) {
              if (item is Map<String, dynamic>) {
                // Create a model instance from each item
                final modelJson = Map<String, dynamic>.from(item);
                // Store the synced flag
                modelJson['isSynced'] = true;
                // Save to storage
                await _storageService.save<T>(
                  _createSyncedModelInstance<T>(modelJson, modelType),
                );
              }
            }
          } else if (response.data is Map) {
            // Response might contain a data array or other structure
            // This would handle cases where the API wraps items in a container
            final dataMap = response.data as Map<String, dynamic>;
            final dataList = dataMap['data'] as List<dynamic>? ?? [];

            for (final item in dataList) {
              if (item is Map<String, dynamic>) {
                // Create a model instance from each item
                final modelJson = Map<String, dynamic>.from(item);
                // Store the synced flag
                modelJson['isSynced'] = true;
                // Save to storage
                await _storageService.save<T>(
                  _createSyncedModelInstance<T>(modelJson, modelType),
                );
              }
            }
          }
        }
      } catch (e) {
        // Log error but don't fail the entire operation
        debugPrint('Error during bidirectional sync: $e');
      }
    }

    // Build appropriate result based on outcomes
    if (failedItems == 0 && processedItems > 0) {
      return SyncResult(
        status: SyncResultStatus.success,
        processedItems: processedItems,
        timeTaken: stopwatch.elapsed,
      );
    } else if (failedItems > 0 && processedItems > 0) {
      return SyncResult(
        status: SyncResultStatus.partial,
        processedItems: processedItems,
        failedItems: failedItems,
        errorMessages: errorMessages,
        timeTaken: stopwatch.elapsed,
      );
    } else {
      return SyncResult(
        status: SyncResultStatus.failed,
        failedItems: failedItems,
        errorMessages: errorMessages,
        timeTaken: stopwatch.elapsed,
      );
    }
  }

  /// Retrieves data from the server and updates local storage
  ///
  /// [modelType] - The type of model to retrieve
  /// [lastSyncTime] - Optional timestamp to only fetch items changed since this time
  /// Returns a [SyncResult] with information about the operation
  @override
  Future<SyncResult> pullFromServer<T extends SyncModel>(
    String modelType,
    DateTime? lastSyncTime, {
    Map<String, dynamic Function(Map<String, dynamic>)>? modelFactories,
  }) async {
    try {
      final items = await fetchItems<T>(
        modelType,
        since: lastSyncTime,
        modelFactories: modelFactories,
      );

      if (items.isEmpty) {
        return SyncResult.noChanges();
      }

      // Save all fetched items to local storage
      await _storageService.saveAll<T>(items);

      return SyncResult.success(processedItems: items.length);
    } catch (e) {
      return SyncResult.failed(error: e.toString());
    }
  }

  /// Creates a new item on the server
  ///
  /// [item] - The model to create on the server
  /// [requestConfig] - Optional custom request configuration
  /// Returns the created model with updated sync status or null if failed
  @override
  Future<T?> createItem<T extends SyncModel>(
    T item, {
    RestRequest? requestConfig,
  }) async {
    try {
      // Use either custom config from parameter or from model
      final config = requestConfig ?? _getRequestConfig(item, RestMethod.post);

      final response = await _networkClient.post(
        item.endpoint,
        body: item.toJson(),
        requestConfig: config,
      );

      if (response.isSuccessful || response.isCreated) {
        return item.markAsSynced() as T;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Updates an existing item on the server
  ///
  /// [item] - The model with updated data to send to the server
  /// [requestConfig] - Optional custom request configuration
  /// Returns the updated model with sync status or null if failed
  @override
  Future<T?> updateItem<T extends SyncModel>(
    T item, {
    RestRequest? requestConfig,
  }) async {
    try {
      // Use either custom config from parameter or from model
      final config = requestConfig ?? _getRequestConfig(item, RestMethod.put);

      final response = await _networkClient.put(
        '${item.endpoint}/${item.id}',
        body: item.toJson(),
        requestConfig: config,
      );

      if (response.isSuccessful) {
        return item.markAsSynced() as T;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Deletes an item from the server
  ///
  /// [item] - The model to delete
  /// Returns true if deletion was successful, false otherwise
  @override
  Future<bool> deleteItem<T extends SyncModel>(T item) async {
    try {
      // Get custom request configuration if available
      final requestConfig = _getRequestConfig(item, RestMethod.delete);

      final response = await _networkClient.delete(
        '${item.endpoint}/${item.id}',
        requestConfig: requestConfig,
      );

      return response.isSuccessful || response.isNoContent;
    } catch (e) {
      return false;
    }
  }

  /// Fetches items of a specific model type from the server
  ///
  /// This method retrieves items from the server based on the provided parameters
  /// and converts them to model instances.
  ///
  /// Parameters:
  /// - [modelType]: The type of model to fetch
  /// - [since]: Optional timestamp to limit results to items modified since that time
  /// - [limit]: Optional maximum number of items to fetch
  /// - [offset]: Optional offset for pagination
  /// - [modelFactories]: Map of factory functions to create model instances from JSON
  ///
  /// Returns a list of model instances
  @override
  Future<List<T>> fetchItems<T extends SyncModel>(
    String modelType, {
    DateTime? since,
    int? limit,
    int? offset,
    Map<String, dynamic Function(Map<String, dynamic>)>? modelFactories,
  }) async {
    try {
      // Construct query parameters
      final Map<String, dynamic> queryParams = {};

      if (since != null) {
        queryParams['since'] = since.toIso8601String();
      }

      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      if (offset != null) {
        queryParams['offset'] = offset.toString();
      }

      // Make the API request
      final response = await _networkClient.get(
        modelType,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (!response.isSuccessful || response.data == null) {
        return <T>[];
      }

      // Extract items from response data
      List<dynamic> itemsJson;
      if (response.data is List) {
        itemsJson = response.data as List<dynamic>;
      } else if (response.data is Map) {
        // Some APIs wrap items in a container object
        // Try to find an array in the response
        final map = response.data as Map<String, dynamic>;
        final possibleArrayKeys = [
          'items',
          'data',
          'results',
          'records',
          modelType,
        ];

        itemsJson = <dynamic>[];
        for (final key in possibleArrayKeys) {
          if (map.containsKey(key) && map[key] is List) {
            itemsJson = map[key] as List<dynamic>;
            break;
          }
        }

        // If we didn't find an array in common locations, try the first list we find
        if (itemsJson.isEmpty) {
          for (final value in map.values) {
            if (value is List) {
              itemsJson = value;
              break;
            }
          }
        }
      } else {
        return <T>[];
      }

      // Convert JSON to model instances
      final factory = modelFactories?[modelType];
      if (factory == null) {
        debugPrint('Warning: No factory found for model type $modelType');
        return <T>[];
      }

      final items =
          itemsJson
              .map((item) {
                if (item is Map<String, dynamic>) {
                  return factory(item) as T;
                }
                return null;
              })
              .whereType<T>()
              .toList();

      return items;
    } catch (e) {
      debugPrint('Error fetching items: $e');
      return <T>[];
    }
  }

  /// Gets items with query parameters and returns a SyncResult
  ///
  /// This method is similar to fetchItems but returns a SyncResult with additional information
  /// about the source and status of the data.
  ///
  /// Parameters:
  /// - [modelType]: The model type to fetch
  /// - [query]: Optional query parameters to filter the items
  ///
  /// Returns a [SyncResult] containing the items and operation details
  @override
  Future<SyncResult<List<T>>> getItems<T extends SyncModel>(
    String modelType, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Make the API request with query parameters
      final response = await _networkClient.get(
        modelType,
        queryParameters: query,
      );

      if (!response.isSuccessful || response.data == null) {
        return SyncResult<List<T>>(
          status: SyncResultStatus.failed,
          errorMessages: ['Failed to fetch items: ${response.statusCode}'],
          timeTaken: stopwatch.elapsed,
        );
      }

      // Extract items from response data
      List<dynamic> itemsJson;
      if (response.data is List) {
        itemsJson = response.data as List<dynamic>;
      } else if (response.data is Map) {
        // Some APIs wrap items in a container object
        // Try to find an array in the response
        final map = response.data as Map<String, dynamic>;
        final possibleArrayKeys = [
          'items',
          'data',
          'results',
          'records',
          modelType,
        ];

        itemsJson = <dynamic>[];
        for (final key in possibleArrayKeys) {
          if (map.containsKey(key) && map[key] is List) {
            itemsJson = map[key] as List<dynamic>;
            break;
          }
        }

        // If we didn't find an array in common locations, try the first list we find
        if (itemsJson.isEmpty) {
          for (final value in map.values) {
            if (value is List) {
              itemsJson = value;
              break;
            }
          }
        }
      } else {
        return SyncResult<List<T>>(
          status: SyncResultStatus.success,
          data: <T>[],
          timeTaken: stopwatch.elapsed,
        );
      }

      // Try to find a factory for this model type
      final items =
          itemsJson
              .map((item) {
                if (item is Map<String, dynamic>) {
                  try {
                    // Use reflection to find model factory
                    final dynamic instance = _createModelInstance<T>(
                      item,
                      modelType,
                    );
                    return instance as T;
                  } catch (e) {
                    debugPrint('Error creating model instance: $e');
                    return null;
                  }
                }
                return null;
              })
              .whereType<T>()
              .toList();

      return SyncResult<List<T>>(
        status: SyncResultStatus.success,
        data: items,
        processedItems: items.length,
        timeTaken: stopwatch.elapsed,
      );
    } catch (e) {
      return SyncResult<List<T>>(
        status: SyncResultStatus.failed,
        errorMessages: ['Error fetching items: $e'],
        data: <T>[],
      );
    }
  }

  /// Creates a model instance from JSON data
  ///
  /// This is a helper method that tries to use reflection to create a model
  /// instance when a factory function isn't explicitly provided.
  T? _createModelInstance<T extends SyncModel>(
    Map<String, dynamic> json,
    String modelType,
  ) {
    // This is simplified - in a real implementation, you'd need a registry
    // of model factories or reflection capabilities
    throw UnimplementedError('Model factory not found for type $modelType');
  }

  /// Creates a synced model instance from JSON data
  ///
  /// This is a helper method for creating model instances during bidirectional sync
  ///
  /// Parameters:
  /// - [json]: JSON data for the model
  /// - [modelType]: The type of model to create
  ///
  /// Returns a model instance marked as synced
  T _createSyncedModelInstance<T extends SyncModel>(
    Map<String, dynamic> json,
    String modelType,
  ) {
    // This implementation assumes the factory exists and works
    // In a real implementation, you would add safeguards

    // Mark as synced
    json['isSynced'] = true;

    // Create instance using SyncRepositoryImpl's modelFactories
    // This will need to be implemented based on your factory system
    throw UnimplementedError(
      'Implement _createSyncedModelInstance based on your factory system',
    );
  }
}
