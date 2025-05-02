import 'dart:async';
import '../models/sync_model.dart';
import '../query/query.dart';

abstract class StorageService {
  Future<void> initialize();

  Future<T?> get<T extends SyncModel>(String id, String modelType);

  Future<List<T>> getAll<T extends SyncModel>(String modelType);

  Future<List<T>> getPending<T extends SyncModel>(String modelType);

  /// Retrieve items of a specific type with optional query parameters
  ///
  /// Parameters:
  /// - [modelType]: The model type to retrieve
  /// - [query]: Optional query parameters to filter the items
  ///
  /// Returns a list of items matching the query
  @Deprecated('Use getItemsWithQuery instead')
  Future<List<T>> getItems<T extends SyncModel>(
    String modelType, {
    Map<String, dynamic>? query,
  });

  /// Retrieve items of a specific type with a structured Query
  ///
  /// This method provides a more powerful and type-safe way to query data
  /// using the Query class which supports where conditions, ordering, and pagination.
  ///
  /// Parameters:
  /// - [modelType]: The model type to retrieve
  /// - [query]: Optional structured query to filter the items
  ///
  /// Returns a list of items matching the query
  Future<List<T>> getItemsWithQuery<T extends SyncModel>(
    String modelType, {
    Query? query,
  });

  Future<void> save<T extends SyncModel>(T model);

  Future<void> saveAll<T extends SyncModel>(List<T> models);

  Future<void> update<T extends SyncModel>(T model);

  /// Delete a model by its ID and type
  Future<void> delete<T extends SyncModel>(String id, String modelType);

  /// Delete a model directly using the model instance
  Future<void> deleteModel<T extends SyncModel>(T model);

  Future<void> markAsSynced<T extends SyncModel>(String id, String modelType);

  Future<void> markSyncFailed<T extends SyncModel>(
    String id,
    String modelType,
    String error,
  );

  Future<int> getPendingCount();

  Future<DateTime> getLastSyncTime();

  Future<void> setLastSyncTime(DateTime time);

  Future<void> clearAll();

  Future<void> close();
}
