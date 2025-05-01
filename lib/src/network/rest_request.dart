import 'package:equatable/equatable.dart';
import '../enums/rest_method.dart';

/// Represents a customizable REST API request configuration
///
/// This class allows for fine-grained control over how HTTP requests
/// are formatted and processed to accommodate different API structures.
class RestRequest extends Equatable {
  /// The HTTP method for this request (GET, POST, PUT, DELETE, PATCH)
  final RestMethod method;

  /// The URL or endpoint path for this request
  final String url;

  /// Additional HTTP headers to include with this request
  final Map<String, String>? headers;

  /// Optional top-level key to wrap the request body in
  ///
  /// For example, if topLevelKey is 'data', the request body will be:
  /// { "data": { ... original body ... } }
  final String? topLevelKey;

  /// Additional top-level data to merge alongside the main request body
  ///
  /// For example, if supplementalTopLevelData is {'documentId': '123'},
  /// the request body will include this field at the top level:
  /// { "documentId": "123", ... other data ... }
  final Map<String, dynamic>? supplementalTopLevelData;

  /// Optional key to extract data from the response
  ///
  /// For example, if responseDataKey is 'documents', the code will
  /// extract response.data['documents'] as the actual data.
  final String? responseDataKey;

  /// URL parameters to replace in the URL string
  ///
  /// For example, if the URL is '/users/{userId}/posts/{postId}' and
  /// urlParameters is {'userId': '123', 'postId': '456'}, the resulting
  /// URL will be '/users/123/posts/456'
  final Map<String, String>? urlParameters;

  /// Request timeout in milliseconds
  ///
  /// Overrides the default timeout for this specific request
  final int? timeoutMillis;

  /// Number of retry attempts for this request in case of failure
  ///
  /// If set, the request will be retried this many times before failing
  final int? retryCount;

  /// Custom response transformer function
  ///
  /// If provided, this function will be called with the raw response data
  /// and should return the transformed data
  final dynamic Function(dynamic data)? responseTransformer;

  /// Creates a new RestRequest instance
  ///
  /// At minimum, [method] and [url] must be provided.
  const RestRequest({
    required this.method,
    required this.url,
    this.headers,
    this.topLevelKey,
    this.supplementalTopLevelData,
    this.responseDataKey,
    this.urlParameters,
    this.timeoutMillis,
    this.retryCount,
    this.responseTransformer,
  });

  /// Creates a copy of this request with the specified fields replaced
  RestRequest copyWith({
    RestMethod? method,
    String? url,
    Map<String, String>? headers,
    String? topLevelKey,
    Map<String, dynamic>? supplementalTopLevelData,
    String? responseDataKey,
    Map<String, String>? urlParameters,
    int? timeoutMillis,
    int? retryCount,
    dynamic Function(dynamic)? responseTransformer,
  }) {
    return RestRequest(
      method: method ?? this.method,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      topLevelKey: topLevelKey ?? this.topLevelKey,
      supplementalTopLevelData:
          supplementalTopLevelData ?? this.supplementalTopLevelData,
      responseDataKey: responseDataKey ?? this.responseDataKey,
      urlParameters: urlParameters ?? this.urlParameters,
      timeoutMillis: timeoutMillis ?? this.timeoutMillis,
      retryCount: retryCount ?? this.retryCount,
      responseTransformer: responseTransformer ?? this.responseTransformer,
    );
  }

  /// Apply URL parameters to replace placeholders in the URL string
  ///
  /// For example, if the URL is '/users/{userId}/posts/{postId}' and
  /// parameters is {'userId': '123', 'postId': '456'}, the result will be
  /// '/users/123/posts/456'
  String getProcessedUrl([Map<String, String>? additionalParams]) {
    if ((urlParameters == null || urlParameters!.isEmpty) &&
        (additionalParams == null || additionalParams.isEmpty)) {
      return url;
    }

    String processedUrl = url;
    final Map<String, String> allParams = {};

    if (urlParameters != null) {
      allParams.addAll(urlParameters!);
    }

    if (additionalParams != null) {
      allParams.addAll(additionalParams);
    }

    for (final entry in allParams.entries) {
      processedUrl = processedUrl.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value),
      );
    }

    return processedUrl;
  }

  /// Creates a RestRequest instance from a JSON map
  factory RestRequest.fromJson(Map<String, dynamic> json) {
    return RestRequest(
      method: _methodFromString(json['method'] as String),
      url: json['url'] as String,
      headers:
          json['headers'] != null
              ? Map<String, String>.from(json['headers'] as Map)
              : null,
      topLevelKey: json['topLevelKey'] as String?,
      supplementalTopLevelData:
          json['supplementalTopLevelData'] != null
              ? Map<String, dynamic>.from(
                json['supplementalTopLevelData'] as Map,
              )
              : null,
      responseDataKey: json['responseDataKey'] as String?,
      urlParameters:
          json['urlParameters'] != null
              ? Map<String, String>.from(json['urlParameters'] as Map)
              : null,
      timeoutMillis: json['timeoutMillis'] as int?,
      retryCount: json['retryCount'] as int?,
    );
  }

  /// Helper method to convert a string to RestMethod enum
  static RestMethod _methodFromString(String methodString) {
    final lowerMethod = methodString.toLowerCase();
    switch (lowerMethod) {
      case 'get':
        return RestMethod.get;
      case 'post':
        return RestMethod.post;
      case 'put':
        return RestMethod.put;
      case 'delete':
        return RestMethod.delete;
      case 'patch':
        return RestMethod.patch;
      default:
        throw ArgumentError('Invalid method: $methodString');
    }
  }

  /// Method name as a string
  String get methodString => method.toString().split('.').last.toUpperCase();

  /// Converts this RestRequest to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'method': methodString,
      'url': url,
      if (headers != null) 'headers': headers,
      if (topLevelKey != null) 'topLevelKey': topLevelKey,
      if (supplementalTopLevelData != null)
        'supplementalTopLevelData': supplementalTopLevelData,
      if (responseDataKey != null) 'responseDataKey': responseDataKey,
      if (urlParameters != null) 'urlParameters': urlParameters,
      if (timeoutMillis != null) 'timeoutMillis': timeoutMillis,
      if (retryCount != null) 'retryCount': retryCount,
    };
  }

  /// Process response data using the custom transformer if available
  dynamic transformResponse(dynamic data) {
    if (responseTransformer != null) {
      return responseTransformer!(data);
    }
    return data;
  }

  @override
  List<Object?> get props => [
    method,
    url,
    headers,
    topLevelKey,
    supplementalTopLevelData,
    responseDataKey,
    urlParameters,
    timeoutMillis,
    retryCount,
  ];
}
