import 'package:offline_sync_kit/offline_sync_kit.dart';

class Todo extends SyncModel {
  final String title;
  final String description;
  final bool isCompleted;
  final int priority;

  Todo({
    super.id,
    super.createdAt,
    super.updatedAt,
    super.isSynced,
    super.syncError,
    super.syncAttempts,
    super.changedFields,
    super.markedForDeletion,
    super.fetchStrategy,
    super.saveStrategy,
    super.deleteStrategy,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.priority = 0,
  });

  @override
  String get endpoint => 'todos';

  @override
  String get modelType => 'todo';

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'priority': priority,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  @override
  Map<String, dynamic> toJsonDelta() {
    final Map<String, dynamic> delta = {'id': id};

    if (changedFields.contains('title')) delta['title'] = title;
    if (changedFields.contains('description')) {
      delta['description'] = description;
    }
    if (changedFields.contains('isCompleted')) {
      delta['isCompleted'] = isCompleted;
    }
    if (changedFields.contains('priority')) delta['priority'] = priority;

    return delta;
  }

  @override
  Todo copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    String? syncError,
    int? syncAttempts,
    Set<String>? changedFields,
    bool? markedForDeletion,
    FetchStrategy? fetchStrategy,
    SaveStrategy? saveStrategy,
    DeleteStrategy? deleteStrategy,
    String? title,
    String? description,
    bool? isCompleted,
    int? priority,
  }) {
    return Todo(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      syncError: syncError ?? this.syncError,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      changedFields: changedFields ?? this.changedFields,
      markedForDeletion: markedForDeletion ?? this.markedForDeletion,
      fetchStrategy: fetchStrategy ?? this.fetchStrategy,
      saveStrategy: saveStrategy ?? this.saveStrategy,
      deleteStrategy: deleteStrategy ?? this.deleteStrategy,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority ?? this.priority,
    );
  }

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
      priority: json['priority'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      isSynced: json['isSynced'] as bool? ?? false,
    );
  }

  // Helper methods - change fields for delta synchronization
  Todo updateTitle(String newTitle) {
    return copyWith(
      title: newTitle,
      changedFields: {...changedFields, 'title'},
      isSynced: false,
    );
  }

  Todo updateDescription(String newDescription) {
    return copyWith(
      description: newDescription,
      changedFields: {...changedFields, 'description'},
      isSynced: false,
    );
  }

  Todo updateCompletionStatus(bool isCompleted) {
    return copyWith(
      isCompleted: isCompleted,
      changedFields: {...changedFields, 'isCompleted'},
      isSynced: false,
    );
  }

  Todo updatePriority(int newPriority) {
    return copyWith(
      priority: newPriority,
      changedFields: {...changedFields, 'priority'},
      isSynced: false,
    );
  }

  Todo markComplete() {
    return copyWith(
      isCompleted: true,
      changedFields: {...changedFields, 'isCompleted'},
      updatedAt: DateTime.now(),
    );
  }

  Todo markIncomplete() {
    return copyWith(
      isCompleted: false,
      changedFields: {...changedFields, 'isCompleted'},
      updatedAt: DateTime.now(),
    );
  }

  Todo withCustomSyncStrategies({
    FetchStrategy? fetchStrategy,
    SaveStrategy? saveStrategy,
    DeleteStrategy? deleteStrategy,
  }) {
    return copyWith(
      fetchStrategy: fetchStrategy,
      saveStrategy: saveStrategy,
      deleteStrategy: deleteStrategy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        isCompleted,
        priority,
        createdAt,
        updatedAt,
        isSynced,
        syncError,
        syncAttempts,
        changedFields,
        markedForDeletion,
        fetchStrategy,
        saveStrategy,
        deleteStrategy,
      ];
}

/// Query examples:
///
/// 1. Simple ID-based query example:
/// ```dart
/// // To find a specific todo by id
/// final query = Query.exact('id', '123');
/// final todo = await storageService.getModel<Todo>(query);
/// ```
///
/// 2. Query example with multiple conditions:
/// ```dart
/// // To find incomplete todos with high priority
/// final query = Query(
///   where: [
///     WhereCondition.exact('isCompleted', false),
///     WhereCondition.greaterThan('priority', 2)
///   ],
///   orderBy: 'priority',
///   descending: true
/// );
/// final todos = await storageService.getAllModels<Todo>(query);
/// ```
///
/// 3. Text search example:
/// ```dart
/// // To find todos containing specific text in title or description
/// final searchQuery = 'important';
/// final query = Query(
///   where: [
///     WhereCondition.contains('title', searchQuery),
///     // To apply OR operator, you need to run multiple queries and combine results
///   ]
/// );
/// final titleMatches = await storageService.getAllModels<Todo>(query);
///
/// // Searching in description
/// final descriptionQuery = Query(
///   where: [WhereCondition.contains('description', searchQuery)]
/// );
/// final descriptionMatches = await storageService.getAllModels<Todo>(descriptionQuery);
///
/// // Combine results and make unique
/// final allMatches = {...titleMatches, ...descriptionMatches}.toList();
/// ```
///
/// 4. Pagination example:
/// ```dart
/// // Pagination retrieving 10 todos at a time
/// int page = 0;
/// int pageSize = 10;
/// 
/// final query = Query(
///   orderBy: 'updatedAt',
///   descending: true,
///   limit: pageSize,
///   offset: page * pageSize
/// );
/// 
/// // To get the next page:
/// page++;
/// final nextPageQuery = query.copyWith(offset: page * pageSize);
/// ```
///
/// 5. Complex query example:
/// ```dart
/// // Get high priority, incomplete todos created in the last 7 days 
/// // that contain "project" in the title
/// final sevenDaysAgo = DateTime.now().subtract(Duration(days: 7));
/// 
/// final query = Query(
///   where: [
///     WhereCondition.greaterThanOrEquals('createdAt', sevenDaysAgo.millisecondsSinceEpoch),
///     WhereCondition.exact('isCompleted', false),
///     WhereCondition.greaterThanOrEquals('priority', 3),
///     WhereCondition.contains('title', 'project')
///   ],
///   orderBy: 'priority',
///   descending: true
/// );
/// 
/// final todos = await storageService.getAllModels<Todo>(query);
/// ```
///
/// 6. SQL generation example:
/// ```dart
/// // To generate SQL query:
/// final query = Query(
///   where: [
///     WhereCondition.exact('isCompleted', false),
///     WhereCondition.greaterThan('priority', 2)
///   ],
///   orderBy: 'updatedAt',
///   descending: true,
///   limit: 20
/// );
/// 
/// final (whereClause, args) = query.toSqlWhereClause();
/// final orderByClause = query.toSqlOrderByClause();
/// final limitClause = query.toSqlLimitOffsetClause();
/// 
/// // Generated SQL parts:
/// // whereClause: "(isCompleted = ? AND priority > ?)"
/// // args: [false, 2]
/// // orderByClause: "ORDER BY updatedAt DESC"
/// // limitClause: "LIMIT 20"
/// ```
