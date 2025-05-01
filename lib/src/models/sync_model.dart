import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../network/rest_requests.dart';

/// Base abstract class for all models that need offline synchronization.
///
/// All models that should be synchronized with a remote API should extend this class.
/// It includes all necessary properties for tracking sync state (sync status, timestamps, etc.).
/// Supports delta synchronization by tracking which fields have been changed since last sync.
///
/// Example:
/// ```dart
/// class Todo extends SyncModel {
///   final String title;
///   final bool isCompleted;
///
///   Todo({
///     super.id,
///     super.createdAt,
///     super.updatedAt,
///     super.isSynced,
///     super.changedFields,
///     required this.title,
///     this.isCompleted = false,
///   });
///
///   @override
///   String get endpoint => 'todos';
///
///   @override
///   String get modelType => 'todo';
///
///   @override
///   Map<String, dynamic> toJson() {
///     return {
///       'id': id,
///       'title': title,
///       'isCompleted': isCompleted,
///     };
///   }
///
///   @override
///   Map<String, dynamic> toJsonDelta() {
///     final Map<String, dynamic> delta = {'id': id};
///     if (changedFields.contains('title')) delta['title'] = title;
///     if (changedFields.contains('isCompleted')) delta['isCompleted'] = isCompleted;
///     return delta;
///   }
///
///   @override
///   Todo copyWith({...}) {
///     // Implementation
///   }
///
///   Todo updateTitle(String newTitle) {
///     return copyWith(
///       title: newTitle,
///       changedFields: {...changedFields, 'title'},
///     );
///   }
/// }
/// ```
abstract class SyncModel extends Equatable {
  /// Unique identifier for the model instance (UUID v4)
  final String id;

  /// Timestamp when the model was first created
  final DateTime createdAt;

  /// Timestamp of the most recent update
  final DateTime updatedAt;

  /// Flag indicating whether this model has been synced with the server
  final bool isSynced;

  /// Error message for the last failed sync attempt, empty if none
  final String syncError;

  /// Number of failed sync attempts for this model
  final int syncAttempts;

  /// Set of field names that have been changed since last sync
  /// Used for delta synchronization to only send changed fields
  final Set<String> changedFields;

  /// Creates a new SyncModel instance
  ///
  /// If [id] is not provided, a new UUID v4 will be generated
  /// If [createdAt] or [updatedAt] are not provided, the current time is used
  /// A new model is not synced by default ([isSynced] = false)
  SyncModel({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.syncError = '',
    this.syncAttempts = 0,
    Set<String>? changedFields,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       changedFields = changedFields ?? <String>{};

  /// The API endpoint for this model type (without leading slash)
  ///
  /// For example: 'todos', 'users', 'products'
  String get endpoint;

  /// A unique string identifier for this model type
  ///
  /// This is used to identify different model types in storage
  /// For example: 'todo', 'user', 'product'
  String get modelType;

  /// Optional custom REST request configurations for this model
  ///
  /// Override this to provide custom request shaping for different APIs
  /// By default, returns null to use standard request formatting
  RestRequests? get restRequests => null;

  /// Converts the model to a JSON map for API requests and storage
  Map<String, dynamic> toJson();

  /// Converts only the changed fields to a JSON map for delta synchronization
  ///
  /// This is used for efficient data transfer when only specific fields have changed.
  /// The implementation includes the model ID and only the fields that are tracked
  /// in the changedFields set.
  ///
  /// Derived classes should override this method for proper delta synchronization.
  Map<String, dynamic> toJsonDelta() {
    // Always include id for record identification
    final Map<String, dynamic> delta = {'id': id};

    // If no specific fields are tracked, return just the ID
    if (changedFields.isEmpty) {
      return delta;
    }

    // Get the full JSON representation
    final fullJson = toJson();

    // Add only changed fields to the delta
    for (final field in changedFields) {
      if (fullJson.containsKey(field)) {
        delta[field] = fullJson[field];
      }
    }

    return delta;
  }

  /// Creates a copy of this model with optionally modified properties
  ///
  /// Allows updating a model immutably. Make sure to implement
  /// this in derived classes to handle custom fields.
  SyncModel copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    String? syncError,
    int? syncAttempts,
    Set<String>? changedFields,
  });

  /// Marks this model as successfully synchronized with the server
  ///
  /// Returns a new instance with [isSynced] = true, cleared [syncError],
  /// and empty [changedFields] since all changes are now synced
  SyncModel markAsSynced() {
    return copyWith(
      isSynced: true,
      syncError: '',
      updatedAt: DateTime.now(),
      changedFields: <String>{},
    );
  }

  /// Marks this model as failed to synchronize
  ///
  /// Returns a new instance with [isSynced] = false, increased [syncAttempts],
  /// and the [error] message stored in [syncError]
  SyncModel markSyncFailed(String error) {
    return copyWith(
      isSynced: false,
      syncError: error,
      syncAttempts: syncAttempts + 1,
      updatedAt: DateTime.now(),
    );
  }

  /// Returns true if this model has any unsynchronized changes
  bool get hasChanges => changedFields.isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    createdAt,
    updatedAt,
    isSynced,
    syncError,
    syncAttempts,
    changedFields,
  ];
}
