import 'package:equatable/equatable.dart';
import '../enums/rest_method.dart';
import 'rest_request.dart';

/// Container class to hold request configurations for different HTTP methods
///
/// This class allows specifying custom request configurations for each
/// HTTP method (GET, POST, PUT, DELETE, PATCH) separately.
class RestRequests extends Equatable {
  /// Configuration for GET requests
  final RestRequest? get;

  /// Configuration for POST requests
  final RestRequest? post;

  /// Configuration for PUT requests
  final RestRequest? put;

  /// Configuration for DELETE requests
  final RestRequest? delete;

  /// Configuration for PATCH requests
  final RestRequest? patch;

  /// Creates a new RestRequests instance
  ///
  /// All parameters are optional - only define the ones you need to customize
  const RestRequests({this.get, this.post, this.put, this.delete, this.patch});

  /// Creates a copy of this object with the specified fields replaced
  RestRequests copyWith({
    RestRequest? get,
    RestRequest? post,
    RestRequest? put,
    RestRequest? delete,
    RestRequest? patch,
  }) {
    return RestRequests(
      get: get ?? this.get,
      post: post ?? this.post,
      put: put ?? this.put,
      delete: delete ?? this.delete,
      patch: patch ?? this.patch,
    );
  }

  /// Creates a RestRequests instance from a JSON map
  factory RestRequests.fromJson(Map<String, dynamic> json) {
    return RestRequests(
      get:
          json['get'] != null
              ? RestRequest.fromJson(json['get'] as Map<String, dynamic>)
              : null,
      post:
          json['post'] != null
              ? RestRequest.fromJson(json['post'] as Map<String, dynamic>)
              : null,
      put:
          json['put'] != null
              ? RestRequest.fromJson(json['put'] as Map<String, dynamic>)
              : null,
      delete:
          json['delete'] != null
              ? RestRequest.fromJson(json['delete'] as Map<String, dynamic>)
              : null,
      patch:
          json['patch'] != null
              ? RestRequest.fromJson(json['patch'] as Map<String, dynamic>)
              : null,
    );
  }

  /// Converts this RestRequests to a JSON map
  Map<String, dynamic> toJson() {
    return {
      if (get != null) 'get': get!.toJson(),
      if (post != null) 'post': post!.toJson(),
      if (put != null) 'put': put!.toJson(),
      if (delete != null) 'delete': delete!.toJson(),
      if (patch != null) 'patch': patch!.toJson(),
    };
  }

  /// Gets the request configuration for the specified HTTP method
  ///
  /// [method] The REST method enum (GET, POST, PUT, DELETE, PATCH)
  /// Returns the corresponding RestRequest or null if not configured
  RestRequest? getForMethod(RestMethod method) {
    switch (method) {
      case RestMethod.get:
        return get;
      case RestMethod.post:
        return post;
      case RestMethod.put:
        return put;
      case RestMethod.delete:
        return delete;
      case RestMethod.patch:
        return patch;
    }
  }

  /// Gets the request configuration for the specified HTTP method as string
  ///
  /// This is provided for backward compatibility
  ///
  /// [methodString] The HTTP method as a string ('GET', 'POST', etc.)
  /// Returns the corresponding RestRequest or null if not configured
  RestRequest? getForMethodString(String methodString) {
    final upperMethod = methodString.toUpperCase();
    switch (upperMethod) {
      case 'GET':
        return get;
      case 'POST':
        return post;
      case 'PUT':
        return put;
      case 'DELETE':
        return delete;
      case 'PATCH':
        return patch;
      default:
        return null;
    }
  }

  @override
  List<Object?> get props => [get, post, put, delete, patch];
}
