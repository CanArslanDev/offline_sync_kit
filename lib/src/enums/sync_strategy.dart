/// Defines different strategies for handling delete operations in offline-first mode.
enum DeleteStrategy {
  /// Delete local data immediately before waiting for the remote response.
  /// Provides better user experience but may lead to inconsistency if remote operation fails.
  optimisticDelete,

  /// Delete local data only after successful remote deletion.
  /// More consistent but may appear slower to users.
  waitForRemote,
}

/// Defines strategies for retrieving data with offline-first approach.
enum FetchStrategy {
  /// Returns local data immediately while fetching from remote in the background.
  /// Remote fetch happens on every call but is not awaited.
  backgroundSync,

  /// Always waits for remote data before returning results.
  /// Returns empty if offline or remote fails.
  remoteFirst,

  /// Uses local data if available, otherwise waits for remote data.
  /// Good balance between performance and freshness.
  localWithRemoteFallback,

  /// Only uses locally cached data without any remote operations.
  /// Fastest but may return stale data.
  localOnly,
}

/// Defines strategies for save operations (insert/update) in offline-first mode.
enum SaveStrategy {
  /// Saves data locally immediately before waiting for remote response.
  /// Better user experience but may lead to inconsistency if remote operation fails.
  optimisticSave,

  /// Saves data locally only after successful remote operation.
  /// More consistent but may appear slower to users.
  waitForRemote,
}
