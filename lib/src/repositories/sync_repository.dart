import 'dart:async';
import '../models/sync_model.dart';
import '../models/sync_result.dart';
import '../network/rest_request.dart';

abstract class SyncRepository {
  Future<SyncResult> syncItem<T extends SyncModel>(T item);

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
  Future<SyncResult> syncDelta<T extends SyncModel>(
    T item,
    Map<String, dynamic> changedFields,
  );

  Future<SyncResult> syncAll<T extends SyncModel>(
    List<T> items, {
    bool bidirectional = true,
  });

  Future<SyncResult> pullFromServer<T extends SyncModel>(
    String modelType,
    DateTime? lastSyncTime, {
    Map<String, dynamic Function(Map<String, dynamic>)>? modelFactories,
  });

  /// Creates a new item on the server
  ///
  /// Parameters:
  /// - [item]: The model to create
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns the created model with updated sync status or null if failed
  Future<T?> createItem<T extends SyncModel>(
    T item, {
    RestRequest? requestConfig,
  });

  /// Updates an existing item on the server
  ///
  /// Parameters:
  /// - [item]: The model to update
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns the updated model with sync status or null if failed
  Future<T?> updateItem<T extends SyncModel>(
    T item, {
    RestRequest? requestConfig,
  });

  Future<bool> deleteItem<T extends SyncModel>(T item);

  /// Fetches items of a specific model type from the server
  ///
  /// [modelType] - The type of model to fetch
  /// [since] - Optional timestamp to only fetch items modified since this time
  /// [limit] - Optional maximum number of items to fetch
  /// [offset] - Optional offset for pagination
  /// [modelFactories] - Map of model factories to create instances from JSON
  /// Returns a list of model instances
  Future<List<T>> fetchItems<T extends SyncModel>(
    String modelType, {
    DateTime? since,
    int? limit,
    int? offset,
    Map<String, dynamic Function(Map<String, dynamic>)>? modelFactories,
  });

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
  Future<SyncResult<List<T>>> getItems<T extends SyncModel>(
    String modelType, {
    Map<String, dynamic>? query,
  });
}
