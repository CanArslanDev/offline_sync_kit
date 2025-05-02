import 'package:equatable/equatable.dart';

/// Type of comparison operator used in a where condition
enum WhereOperator {
  /// field == value
  equals,

  /// field != value
  notEquals,

  /// field > value
  greaterThan,

  /// field >= value
  greaterThanOrEquals,

  /// field < value
  lessThan,

  /// field <= value
  lessThanOrEquals,

  /// field LIKE '%value%'
  contains,

  /// field LIKE 'value%'
  startsWith,

  /// field LIKE '%value'
  endsWith,

  /// field IN (value1, value2, ...)
  inList,

  /// field IS NULL
  isNull,

  /// field IS NOT NULL
  isNotNull,
}

/// Represents a condition for filtering data in queries.
///
/// This class defines conditions like equals, greater than, contains, etc.
/// that can be used to filter data in the query system.
///
/// Example:
/// ```dart
/// final condition = WhereCondition.exact('name', 'John');
/// final greaterThan = WhereCondition.greaterThan('age', 18);
/// ```
class WhereCondition extends Equatable {
  /// The field name to filter on
  final String field;

  /// The value to compare against
  final dynamic value;

  /// The comparison operator
  final WhereOperator operator;

  /// Creates a new where condition.
  ///
  /// [field] - The field name to filter on
  /// [value] - The value to compare against
  /// [operator] - The comparison operator
  const WhereCondition({
    required this.field,
    required this.operator,
    this.value,
  });

  /// Creates a condition checking for equality.
  ///
  /// This is equivalent to `field = value` in SQL.
  factory WhereCondition.exact(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.equals,
      value: value,
    );
  }

  /// Creates a condition checking for inequality.
  ///
  /// This is equivalent to `field != value` in SQL.
  factory WhereCondition.notEquals(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.notEquals,
      value: value,
    );
  }

  /// Creates a condition checking if field is greater than value.
  ///
  /// This is equivalent to `field > value` in SQL.
  factory WhereCondition.greaterThan(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.greaterThan,
      value: value,
    );
  }

  /// Creates a condition checking if field is greater than or equal to value.
  ///
  /// This is equivalent to `field >= value` in SQL.
  factory WhereCondition.greaterThanOrEquals(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.greaterThanOrEquals,
      value: value,
    );
  }

  /// Creates a condition checking if field is less than value.
  ///
  /// This is equivalent to `field < value` in SQL.
  factory WhereCondition.lessThan(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.lessThan,
      value: value,
    );
  }

  /// Creates a condition checking if field is less than or equal to value.
  ///
  /// This is equivalent to `field <= value` in SQL.
  factory WhereCondition.lessThanOrEquals(String field, dynamic value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.lessThanOrEquals,
      value: value,
    );
  }

  /// Creates a condition checking if field contains value.
  ///
  /// This is equivalent to `field LIKE '%value%'` in SQL.
  factory WhereCondition.contains(String field, String value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.contains,
      value: value,
    );
  }

  /// Creates a condition checking if field starts with value.
  ///
  /// This is equivalent to `field LIKE 'value%'` in SQL.
  factory WhereCondition.startsWith(String field, String value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.startsWith,
      value: value,
    );
  }

  /// Creates a condition checking if field ends with value.
  ///
  /// This is equivalent to `field LIKE '%value'` in SQL.
  factory WhereCondition.endsWith(String field, String value) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.endsWith,
      value: value,
    );
  }

  /// Creates a condition checking if field is in a list of values.
  ///
  /// This is equivalent to `field IN (value1, value2, ...)` in SQL.
  factory WhereCondition.inList(String field, List<dynamic> values) {
    return WhereCondition(
      field: field,
      operator: WhereOperator.inList,
      value: values,
    );
  }

  /// Creates a condition checking if field is null.
  ///
  /// This is equivalent to `field IS NULL` in SQL.
  factory WhereCondition.isNull(String field) {
    return WhereCondition(field: field, operator: WhereOperator.isNull);
  }

  /// Creates a condition checking if field is not null.
  ///
  /// This is equivalent to `field IS NOT NULL` in SQL.
  factory WhereCondition.isNotNull(String field) {
    return WhereCondition(field: field, operator: WhereOperator.isNotNull);
  }

  /// Converts this condition to a SQL clause.
  ///
  /// This is used internally by the query system to generate SQL.
  ///
  /// Returns a tuple of (clause, arguments) where:
  /// - clause is the SQL WHERE clause fragment
  /// - arguments is the list of arguments for the prepared statement
  (String, List<dynamic>) toSqlClause() {
    switch (operator) {
      case WhereOperator.equals:
        return ('$field = ?', [value]);
      case WhereOperator.notEquals:
        return ('$field != ?', [value]);
      case WhereOperator.greaterThan:
        return ('$field > ?', [value]);
      case WhereOperator.greaterThanOrEquals:
        return ('$field >= ?', [value]);
      case WhereOperator.lessThan:
        return ('$field < ?', [value]);
      case WhereOperator.lessThanOrEquals:
        return ('$field <= ?', [value]);
      case WhereOperator.contains:
        return ('$field LIKE ?', ['%$value%']);
      case WhereOperator.startsWith:
        return ('$field LIKE ?', ['$value%']);
      case WhereOperator.endsWith:
        return ('$field LIKE ?', ['%$value']);
      case WhereOperator.inList:
        final List<dynamic> values = value as List<dynamic>;
        final placeholders = List.filled(values.length, '?').join(', ');
        return ('$field IN ($placeholders)', values);
      case WhereOperator.isNull:
        return ('$field IS NULL', []);
      case WhereOperator.isNotNull:
        return ('$field IS NOT NULL', []);
    }
  }

  /// Checks if this condition matches an item.
  ///
  /// This is used when applying queries in memory rather than via SQL.
  ///
  /// [item] - The item to check
  /// [getField] - A function that extracts a field value from the item
  ///
  /// Returns true if the condition matches the item
  bool matches<T>(T item, dynamic Function(T item, String field) getField) {
    final fieldValue = getField(item, field);

    switch (operator) {
      case WhereOperator.equals:
        return fieldValue == value;
      case WhereOperator.notEquals:
        return fieldValue != value;
      case WhereOperator.greaterThan:
        if (fieldValue == null) return false;
        if (fieldValue is Comparable && value is Comparable) {
          return Comparable.compare(fieldValue, value as Comparable) > 0;
        }
        return false;
      case WhereOperator.greaterThanOrEquals:
        if (fieldValue == null) return false;
        if (fieldValue is Comparable && value is Comparable) {
          return Comparable.compare(fieldValue, value as Comparable) >= 0;
        }
        return false;
      case WhereOperator.lessThan:
        if (fieldValue == null) return false;
        if (fieldValue is Comparable && value is Comparable) {
          return Comparable.compare(fieldValue, value as Comparable) < 0;
        }
        return false;
      case WhereOperator.lessThanOrEquals:
        if (fieldValue == null) return false;
        if (fieldValue is Comparable && value is Comparable) {
          return Comparable.compare(fieldValue, value as Comparable) <= 0;
        }
        return false;
      case WhereOperator.contains:
        if (fieldValue == null) return false;
        return fieldValue.toString().contains(value.toString());
      case WhereOperator.startsWith:
        if (fieldValue == null) return false;
        return fieldValue.toString().startsWith(value.toString());
      case WhereOperator.endsWith:
        if (fieldValue == null) return false;
        return fieldValue.toString().endsWith(value.toString());
      case WhereOperator.inList:
        if (fieldValue == null) return false;
        return (value as List).contains(fieldValue);
      case WhereOperator.isNull:
        return fieldValue == null;
      case WhereOperator.isNotNull:
        return fieldValue != null;
    }
  }

  @override
  List<Object?> get props => [field, operator, value];

  @override
  String toString() {
    switch (operator) {
      case WhereOperator.equals:
        return '$field = $value';
      case WhereOperator.notEquals:
        return '$field != $value';
      case WhereOperator.greaterThan:
        return '$field > $value';
      case WhereOperator.greaterThanOrEquals:
        return '$field >= $value';
      case WhereOperator.lessThan:
        return '$field < $value';
      case WhereOperator.lessThanOrEquals:
        return '$field <= $value';
      case WhereOperator.contains:
        return '$field CONTAINS "$value"';
      case WhereOperator.startsWith:
        return '$field STARTS WITH "$value"';
      case WhereOperator.endsWith:
        return '$field ENDS WITH "$value"';
      case WhereOperator.inList:
        return '$field IN $value';
      case WhereOperator.isNull:
        return '$field IS NULL';
      case WhereOperator.isNotNull:
        return '$field IS NOT NULL';
    }
  }
}
