import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join;
import '../models/sync_model.dart';
import '../query/query.dart';
import 'storage_service.dart';

class StorageServiceImpl implements StorageService {
  static const String _dbName = 'offline_sync.db';
  static const int _dbVersion = 1;
  static const String _syncTable = 'sync_items';
  static const String _metaTable = 'sync_meta';

  Database? _db;
  final Map<String, Function> _modelDeserializers = {};

  @override
  Future<void> initialize({
    String? directory,
    DatabaseFactory? databaseFactoryCustom,
  }) async {
    if (_db != null) return;

    final documentsDirectory =
        directory ?? (await getApplicationDocumentsDirectory()).path;
    final path = join(documentsDirectory, _dbName);
    databaseFactoryCustom ??= databaseFactory;
    _db = await databaseFactoryCustom.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _dbVersion, onCreate: _createDb),
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_syncTable (
        id TEXT PRIMARY KEY,
        model_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL,
        sync_error TEXT,
        sync_attempts INTEGER NOT NULL,
        data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_metaTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.insert(_metaTable, {
      'key': 'last_sync_time',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void registerModelDeserializer<T extends SyncModel>(
    String modelType,
    T Function(Map<String, dynamic> json) deserializer,
  ) {
    _modelDeserializers[modelType] = deserializer;
  }

  @override
  Future<T?> get<T extends SyncModel>(String id, String modelType) async {
    await initialize();

    final result = await _db!.query(
      _syncTable,
      where: 'id = ? AND model_type = ?',
      whereArgs: [id, modelType],
    );

    if (result.isEmpty) {
      return null;
    }

    return _deserializeModel<T>(result.first);
  }

  @override
  Future<List<T>> getAll<T extends SyncModel>(String modelType) async {
    await initialize();

    final result = await _db!.query(
      _syncTable,
      where: 'model_type = ?',
      whereArgs: [modelType],
    );

    return result.map<T>((row) => _deserializeModel<T>(row)!).toList();
  }

  @override
  Future<List<T>> getPending<T extends SyncModel>(String modelType) async {
    await initialize();

    final result = await _db!.query(
      _syncTable,
      where: 'model_type = ? AND is_synced = 0',
      whereArgs: [modelType],
    );

    return result.map<T>((row) => _deserializeModel<T>(row)!).toList();
  }

  @override
  Future<List<T>> getItems<T extends SyncModel>(
    String modelType, {
    Map<String, dynamic>? query,
  }) async {
    await initialize();

    // For simplicity in the initial implementation, just get all items of the model type
    // The JSON query filtering would require more sophisticated implementation
    final result = await _db!.query(
      _syncTable,
      where: 'model_type = ?',
      whereArgs: [modelType],
    );

    // If there's no additional filtering needed, return all items
    if (query == null || query.isEmpty) {
      return result.map<T>((row) => _deserializeModel<T>(row)!).toList();
    }

    // Deserialize all items first
    final allItems =
        result.map<T>((row) => _deserializeModel<T>(row)!).toList();

    // Then filter them in memory based on the query parameters
    return allItems.where((item) {
      final itemJson = item.toJson();

      // Check if all query parameters match
      return query.entries.every((entry) {
        final key = entry.key;
        final value = entry.value;

        // Skip null values
        if (value == null) return true;

        // Make sure the item has this field
        if (!itemJson.containsKey(key)) return false;

        // Check if values match
        if (value is List) {
          return value.contains(itemJson[key]);
        } else {
          return itemJson[key] == value;
        }
      });
    }).toList();
  }

  @override
  Future<List<T>> getItemsWithQuery<T extends SyncModel>(
    String modelType, {
    Query? query,
  }) async {
    await initialize();

    if (query == null) {
      // If no query is provided, return all items of this type
      return getAll<T>(modelType);
    }

    try {
      // Try to use SQL-based filtering if possible
      return await _getItemsWithSqlQuery<T>(modelType, query);
    } catch (e) {
      // Fallback to in-memory filtering if SQL approach fails
      return _getItemsWithInMemoryFiltering<T>(modelType, query);
    }
  }

  // Gets items using direct SQL queries for better performance
  Future<List<T>> _getItemsWithSqlQuery<T extends SyncModel>(
    String modelType,
    Query query,
  ) async {
    // Base query always filters by model_type
    String whereClause = 'model_type = ?';
    List<dynamic> whereArgs = [modelType];

    // Add query conditions if present
    if (query.where != null && query.where!.isNotEmpty) {
      final (queryWhereClause, queryArgs) = query.toSqlWhereClause();
      if (queryWhereClause.isNotEmpty) {
        whereClause += ' AND $queryWhereClause';
        whereArgs.addAll(queryArgs);
      }
    }

    // Prepare ordering
    String? orderBy;
    if (query.orderBy != null) {
      // Map field name to database column
      // Most fields are stored in the JSON data, but we can handle special cases
      String orderField;
      switch (query.orderBy) {
        case 'createdAt':
          orderField = 'created_at';
          break;
        case 'updatedAt':
          orderField = 'updated_at';
          break;
        default:
          // For data stored in JSON, we can't directly order in SQL
          // We'll need to use memory-based filtering instead
          throw UnsupportedError(
            'SQL ordering not supported for field: ${query.orderBy}',
          );
      }

      orderBy = '$orderField ${query.descending ? 'DESC' : 'ASC'}';
    }

    // Execute the query
    final result = await _db!.query(
      _syncTable,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: query.limit,
      offset: query.offset,
    );

    return result.map<T>((row) => _deserializeModel<T>(row)!).toList();
  }

  // Fallback method that uses in-memory filtering
  Future<List<T>> _getItemsWithInMemoryFiltering<T extends SyncModel>(
    String modelType,
    Query query,
  ) async {
    // Get all items of this type first
    final allItems = await getAll<T>(modelType);

    // Apply the query filter
    return query.applyToList<T>(allItems, (item, field) {
      // Extract field value from the item
      switch (field) {
        case 'id':
          return item.id;
        case 'createdAt':
          return item.createdAt.millisecondsSinceEpoch;
        case 'updatedAt':
          return item.updatedAt.millisecondsSinceEpoch;
        case 'isSynced':
          return item.isSynced;
        default:
          // For other fields, get from the JSON data
          final json = item.toJson();
          return json[field];
      }
    });
  }

  @override
  Future<void> save<T extends SyncModel>(T model) async {
    await initialize();

    await _db!.insert(
      _syncTable,
      _serializeModel(model),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveAll<T extends SyncModel>(List<T> models) async {
    await initialize();

    final batch = _db!.batch();

    for (final model in models) {
      batch.insert(
        _syncTable,
        _serializeModel(model),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  @override
  Future<void> update<T extends SyncModel>(T model) async {
    await initialize();

    await _db!.update(
      _syncTable,
      _serializeModel(model),
      where: 'id = ?',
      whereArgs: [model.id],
    );
  }

  @override
  Future<void> delete<T extends SyncModel>(String id, String modelType) async {
    await initialize();

    await _db!.delete(
      _syncTable,
      where: 'id = ? AND model_type = ?',
      whereArgs: [id, modelType],
    );
  }

  @override
  Future<void> deleteModel<T extends SyncModel>(T model) async {
    await delete<T>(model.id, model.modelType);
  }

  @override
  Future<void> markAsSynced<T extends SyncModel>(
    String id,
    String modelType,
  ) async {
    await initialize();

    final item = await get<T>(id, modelType);

    if (item != null) {
      final syncedItem = item.markAsSynced();
      await update(syncedItem);
    }
  }

  @override
  Future<void> markSyncFailed<T extends SyncModel>(
    String id,
    String modelType,
    String error,
  ) async {
    await initialize();

    final item = await get<T>(id, modelType);

    if (item != null) {
      final failedItem = item.markSyncFailed(error);
      await update(failedItem);
    }
  }

  @override
  Future<int> getPendingCount() async {
    await initialize();

    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as count FROM $_syncTable WHERE is_synced = 0',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<DateTime> getLastSyncTime() async {
    await initialize();

    final result = await _db!.query(
      _metaTable,
      where: 'key = ?',
      whereArgs: ['last_sync_time'],
    );

    if (result.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final timestamp = int.parse(result.first['value'] as String);
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  @override
  Future<void> setLastSyncTime(DateTime time) async {
    await initialize();

    await _db!.update(
      _metaTable,
      {'value': time.millisecondsSinceEpoch.toString()},
      where: 'key = ?',
      whereArgs: ['last_sync_time'],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearAll() async {
    await initialize();

    await _db!.delete(_syncTable);
    await _db!.delete(_metaTable);

    await _db!.insert(_metaTable, {
      'key': 'last_sync_time',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Map<String, dynamic> _serializeModel<T extends SyncModel>(T model) {
    return {
      'id': model.id,
      'model_type': model.modelType,
      'created_at': model.createdAt.millisecondsSinceEpoch,
      'updated_at': model.updatedAt.millisecondsSinceEpoch,
      'is_synced': model.isSynced ? 1 : 0,
      'sync_error': model.syncError,
      'sync_attempts': model.syncAttempts,
      'data': jsonEncode(model.toJson()),
    };
  }

  T? _deserializeModel<T extends SyncModel>(Map<String, dynamic> row) {
    final modelType = row['model_type'] as String;
    final deserializer = _modelDeserializers[modelType];

    if (deserializer == null) {
      throw StateError('No deserializer registered for model type: $modelType');
    }

    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;

    return deserializer(data) as T;
  }
}
