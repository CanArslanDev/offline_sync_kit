import 'package:equatable/equatable.dart';

enum SyncResultStatus {
  success,
  failed,
  partial,
  noChanges,
  connectionError,
  serverError,
}

/// Defines the source of data in a sync result
enum ResultSource {
  /// Data came from the remote provider
  remote,

  /// Data came from local storage
  local,

  /// Data came from local storage due to being offline
  offlineCache,
}

class SyncResult<T> extends Equatable {
  final SyncResultStatus status;
  final int processedItems;
  final int failedItems;
  final List<String> errorMessages;
  final DateTime timestamp;
  final Duration timeTaken;
  final T? data;
  final ResultSource source;

  SyncResult({
    required this.status,
    this.processedItems = 0,
    this.failedItems = 0,
    List<String>? errorMessages,
    DateTime? timestamp,
    this.timeTaken = Duration.zero,
    this.data,
    this.source = ResultSource.remote,
  }) : errorMessages = errorMessages ?? [],
       timestamp = timestamp ?? DateTime.now();

  bool get isSuccessful =>
      status == SyncResultStatus.success ||
      status == SyncResultStatus.noChanges;

  @override
  List<Object?> get props => [
    status,
    processedItems,
    failedItems,
    errorMessages,
    timestamp,
    timeTaken,
    data,
    source,
  ];

  static SyncResult<T> success<T>({
    int processedItems = 0,
    Duration timeTaken = Duration.zero,
    T? data,
    ResultSource source = ResultSource.remote,
  }) {
    return SyncResult<T>(
      status: SyncResultStatus.success,
      processedItems: processedItems,
      timeTaken: timeTaken,
      data: data,
      source: source,
    );
  }

  static SyncResult<T> failed<T>({
    String error = '',
    Duration timeTaken = Duration.zero,
  }) {
    return SyncResult<T>(
      status: SyncResultStatus.failed,
      errorMessages: error.isNotEmpty ? [error] : [],
      timeTaken: timeTaken,
    );
  }

  static SyncResult<T> noChanges<T>() {
    return SyncResult<T>(status: SyncResultStatus.noChanges);
  }

  static SyncResult<T> connectionError<T>() {
    return SyncResult<T>(
      status: SyncResultStatus.connectionError,
      errorMessages: ['No internet connection available'],
      source: ResultSource.offlineCache,
    );
  }
}
