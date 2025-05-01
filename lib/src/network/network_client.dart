import 'dart:async';
import 'rest_request.dart';

abstract class NetworkClient {
  Future<NetworkResponse> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    RestRequest? requestConfig,
  });

  Future<NetworkResponse> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  });

  Future<NetworkResponse> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  });

  Future<NetworkResponse> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  });

  Future<NetworkResponse> delete(
    String endpoint, {
    Map<String, String>? headers,
    RestRequest? requestConfig,
  });
}

class NetworkResponse {
  final int statusCode;
  final dynamic data;
  final String error;
  final Map<String, String> headers;

  const NetworkResponse({
    required this.statusCode,
    this.data,
    this.error = '',
    this.headers = const {},
  });

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  bool get isCreated => statusCode == 201;

  bool get isNoContent => statusCode == 204;

  bool get isBadRequest => statusCode == 400;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  bool get isServerError => statusCode >= 500;
}
