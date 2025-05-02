import 'package:equatable/equatable.dart';
import 'where_condition.dart';

/// Sort direction for query ordering
enum SortDirection {
  /// Ascending order (A-Z, 0-9)
  ascending,

  /// Descending order (Z-A, 9-0)
  descending,
}

/// A structured query for database operations.
///
/// This class provides a way to build SQL-like queries for filtering data
/// in the offline storage system. It supports where conditions, ordering,
/// pagination, and more.
///
/// Example:
/// ```dart
/// // Traditional constructor usage
/// final query = Query(
///   where: [WhereCondition.exact('name', 'John'), WhereCondition.greaterThan('age', 18)],
///   orderBy: 'createdAt',
///   descending: true,
///   limit: 10,
/// );
///
/// // Fluent API usage
/// final fluentQuery = Query()
///   .addWhere(WhereCondition.exact('name', 'John'))
///   .addWhere(WhereCondition.greaterThan('age', 18))
///   .addOrderBy('createdAt', direction: SortDirection.descending)
///   .page(0, pageSize: 10);
/// ```
class Query extends Equatable {
  /// List of where conditions for filtering
  final List<WhereCondition>? where;

  /// Field to order results by
  final String? orderBy;

  /// Whether to sort in descending order
  final bool descending;

  /// Maximum number of results to return
  final int? limit;

  /// Number of results to skip
  final int? offset;

  /// Creates a new query.
  ///
  /// [where] - List of where conditions for filtering results
  /// [orderBy] - Field name to order results by
  /// [descending] - Whether to sort in descending order
  /// [limit] - Maximum number of results to return
  /// [offset] - Number of results to skip (for pagination)
  const Query({
    this.where,
    this.orderBy,
    this.descending = false,
    this.limit,
    this.offset,
  });

  /// Creates a new query with only the given where conditions.
  ///
  /// This is a convenience constructor for simple queries.
  factory Query.where(List<WhereCondition> conditions) {
    return Query(where: conditions);
  }

  /// Creates a new query that filters for a single exact match.
  ///
  /// This is a convenience constructor for the common case of
  /// finding an item by a single field value.
  factory Query.exact(String field, dynamic value) {
    return Query(where: [WhereCondition.exact(field, value)]);
  }

  /// Creates a copy of this query with the given fields replaced.
  Query copyWith({
    List<WhereCondition>? where,
    String? orderBy,
    bool? descending,
    int? limit,
    int? offset,
  }) {
    return Query(
      where: where ?? this.where,
      orderBy: orderBy ?? this.orderBy,
      descending: descending ?? this.descending,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  /// Adds a where condition to this query.
  ///
  /// Returns a new query with the added condition.
  Query addWhere(WhereCondition condition) {
    final newWhere = [...?where, condition];
    return copyWith(where: newWhere);
  }

  /// Sets the ordering field and direction for this query.
  ///
  /// [field] - The field to order by
  /// [direction] - The sort direction (ascending or descending)
  ///
  /// Returns a new query with the ordering applied.
  Query addOrderBy(
    String field, {
    SortDirection direction = SortDirection.ascending,
  }) {
    return copyWith(
      orderBy: field,
      descending: direction == SortDirection.descending,
    );
  }

  /// Sets pagination parameters for this query.
  ///
  /// [pageNumber] - The zero-based page number
  /// [pageSize] - The number of items per page
  ///
  /// Returns a new query with pagination applied.
  Query page(int pageNumber, {int pageSize = 20}) {
    return copyWith(limit: pageSize, offset: pageNumber * pageSize);
  }

  /// Sets a limit on the number of results returned.
  ///
  /// [count] - Maximum number of results to return
  ///
  /// Returns a new query with the limit applied.
  Query limitTo(int count) {
    return copyWith(limit: count);
  }

  /// Sets an offset for the results.
  ///
  /// [count] - Number of results to skip
  ///
  /// Returns a new query with the offset applied.
  Query offsetBy(int count) {
    return copyWith(offset: count);
  }

  /// Converts this query to a SQL WHERE clause.
  ///
  /// This is used internally by the storage implementation.
  ///
  /// Returns a tuple of (whereClause, arguments) where:
  /// - whereClause is the SQL WHERE clause string
  /// - arguments is the list of arguments for the prepared statement
  (String, List<dynamic>) toSqlWhereClause() {
    if (where == null || where!.isEmpty) {
      return ('', []);
    }

    final clauses = <String>[];
    final args = <dynamic>[];

    for (final condition in where!) {
      final (clause, conditionArgs) = condition.toSqlClause();
      clauses.add(clause);
      args.addAll(conditionArgs);
    }

    return ('(${clauses.join(' AND ')})', args);
  }

  /// Converts this query to a SQL ORDER BY clause.
  ///
  /// This is used internally by the storage implementation.
  String toSqlOrderByClause() {
    if (orderBy == null) {
      return '';
    }

    return 'ORDER BY $orderBy ${descending ? 'DESC' : 'ASC'}';
  }

  /// Converts this query to a SQL LIMIT/OFFSET clause.
  ///
  /// This is used internally by the storage implementation.
  String toSqlLimitOffsetClause() {
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final offsetClause = offset != null ? 'OFFSET $offset' : '';

    if (limitClause.isNotEmpty && offsetClause.isNotEmpty) {
      return '$limitClause $offsetClause';
    }

    return limitClause + offsetClause;
  }

  /// Applies this query to filter a list of items in memory.
  ///
  /// This is used when SQL filtering is not available.
  ///
  /// [items] - The list of items to filter
  /// [getField] - A function that extracts a field value from an item
  ///
  /// Returns the filtered list
  List<T> applyToList<T>(
    List<T> items,
    dynamic Function(T item, String field) getField,
  ) {
    // Start with the full list
    var result = List<T>.from(items);

    // Apply where conditions
    if (where != null && where!.isNotEmpty) {
      result =
          result.where((item) {
            // Item must match all where conditions
            return where!.every((condition) {
              return condition.matches(item, getField);
            });
          }).toList();
    }

    // Apply ordering
    if (orderBy != null) {
      result.sort((a, b) {
        final aValue = getField(a, orderBy!);
        final bValue = getField(b, orderBy!);

        // Handle null values
        if (aValue == null && bValue == null) return 0;
        if (aValue == null) return descending ? 1 : -1;
        if (bValue == null) return descending ? -1 : 1;

        // Compare based on type
        int compareResult;

        if (aValue is Comparable && bValue is Comparable) {
          compareResult = Comparable.compare(aValue, bValue);
        } else {
          // Fall back to string comparison
          compareResult = aValue.toString().compareTo(bValue.toString());
        }

        return descending ? -compareResult : compareResult;
      });
    }

    // Apply pagination
    if (offset != null && offset! > 0) {
      if (offset! >= result.length) {
        return <T>[];
      }
      result = result.sublist(offset!);
    }

    if (limit != null && limit! > 0) {
      if (limit! < result.length) {
        result = result.sublist(0, limit);
      }
    }

    return result;
  }

  @override
  List<Object?> get props => [where, orderBy, descending, limit, offset];

  @override
  String toString() {
    final parts = <String>[];

    if (where != null && where!.isNotEmpty) {
      parts.add('where: [${where!.join(', ')}]');
    }

    if (orderBy != null) {
      parts.add('orderBy: $orderBy${descending ? ' DESC' : ''}');
    }

    if (limit != null) {
      parts.add('limit: $limit');
    }

    if (offset != null) {
      parts.add('offset: $offset');
    }

    return 'Query(${parts.join(', ')})';
  }
}
