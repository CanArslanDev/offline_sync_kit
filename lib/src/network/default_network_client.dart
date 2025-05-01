import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_client.dart';
import 'rest_request.dart';

typedef EncryptionHandler =
    Map<String, dynamic> Function(Map<String, dynamic> data);
typedef DecryptionHandler =
    Map<String, dynamic> Function(Map<String, dynamic> data);

/// Default implementation of the NetworkClient interface using the http package
class DefaultNetworkClient implements NetworkClient {
  /// Base URL for all requests
  final String baseUrl;

  /// HTTP client for making requests
  final http.Client _client;

  /// Default headers to apply to all requests
  final Map<String, String> _defaultHeaders;

  /// Optional encryption handler to encrypt outgoing requests
  EncryptionHandler? _encryptionHandler;

  /// Optional decryption handler to decrypt incoming responses
  DecryptionHandler? _decryptionHandler;

  /// Creates a new NetworkClient instance
  ///
  /// Parameters:
  /// - [baseUrl]: The base URL for all requests
  /// - [client]: Optional custom HTTP client
  /// - [defaultHeaders]: Optional default headers to include in all requests
  DefaultNetworkClient({
    required this.baseUrl,
    http.Client? client,
    Map<String, String>? defaultHeaders,
  }) : _client = client ?? http.Client(),
       _defaultHeaders =
           defaultHeaders ??
           {'Content-Type': 'application/json', 'Accept': 'application/json'};

  /// Sets the encryption handler for outgoing requests
  ///
  /// [handler] The function to encrypt data before sending
  void setEncryptionHandler(EncryptionHandler handler) {
    _encryptionHandler = handler;
  }

  /// Sets the decryption handler for incoming responses
  ///
  /// [handler] The function to decrypt data after receiving
  void setDecryptionHandler(DecryptionHandler handler) {
    _decryptionHandler = handler;
  }

  /// Builds a URL from an endpoint and query parameters
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [queryParams]: Optional query parameters to include in the URL
  /// - [requestConfig]: Optional request configuration with URL parameters
  ///
  /// Returns the full URL as a string
  String _buildUrl(
    String endpoint, [
    Map<String, dynamic>? queryParams,
    RestRequest? requestConfig,
  ]) {
    String finalEndpoint = endpoint;
    String finalUrl;

    // If we have a requestConfig with a URL, use that instead of building one
    if (requestConfig != null && requestConfig.url.isNotEmpty) {
      // Process URL parameters if any
      finalUrl = requestConfig.getProcessedUrl();

      // Handle relative vs absolute URLs
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
        finalUrl =
            finalUrl.startsWith('/')
                ? '${cleanBaseUrl}${finalUrl.substring(1)}'
                : '$cleanBaseUrl$finalUrl';
      }
    } else {
      // Use default URL building logic
      final cleanEndpoint =
          endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      finalUrl = '$cleanBaseUrl$cleanEndpoint';
    }

    // Add query parameters if any
    if (queryParams == null || queryParams.isEmpty) {
      return finalUrl;
    }

    final queryString = queryParams.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}',
        )
        .join('&');

    return '$finalUrl${finalUrl.contains('?') ? '&' : '?'}$queryString';
  }

  /// Processes the request body using a RestRequest configuration
  ///
  /// This applies any transformations specified in the RestRequest:
  /// - Wraps the body in a topLevelKey if specified
  /// - Adds supplemental top-level data if specified
  ///
  /// Parameters:
  /// - [body]: The original request body
  /// - [request]: RestRequest configuration to apply
  ///
  /// Returns the transformed request body
  Map<String, dynamic>? _processRequestBody(
    Map<String, dynamic>? body,
    RestRequest? request,
  ) {
    if (body == null) {
      return request?.supplementalTopLevelData;
    }

    Map<String, dynamic> processedBody;

    // Wrap the body in topLevelKey if specified
    if (request?.topLevelKey != null) {
      processedBody = {request!.topLevelKey!: body};
    } else {
      processedBody = Map<String, dynamic>.from(body);
    }

    // Add supplemental top-level data if provided
    if (request?.supplementalTopLevelData != null) {
      processedBody.addAll(request!.supplementalTopLevelData!);
    }

    return processedBody;
  }

  /// Processes the response data using a RestRequest configuration
  ///
  /// This extracts data from the specified responseDataKey if provided
  ///
  /// Parameters:
  /// - [data]: The original response data
  /// - [request]: RestRequest configuration to apply
  ///
  /// Returns the processed response data
  dynamic _processResponseData(dynamic data, RestRequest? request) {
    if (data == null || request?.responseDataKey == null) {
      return data;
    }

    if (data is Map<String, dynamic> &&
        data.containsKey(request!.responseDataKey!)) {
      return data[request.responseDataKey!];
    }

    return data;
  }

  /// Sends a GET request to the specified endpoint
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [queryParameters]: Optional query parameters to include in the URL
  /// - [headers]: Optional headers to include in the request
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns a [NetworkResponse] with the result of the request
  @override
  Future<NetworkResponse> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) async {
    final url = _buildUrl(endpoint, queryParameters, requestConfig);

    // Apply timeout if specified
    final timeout =
        requestConfig?.timeoutMillis != null
            ? Duration(milliseconds: requestConfig!.timeoutMillis!)
            : null;

    // Handle retries if configured
    int attemptCount = 0;
    final maxAttempts = (requestConfig?.retryCount ?? 0) + 1;

    while (true) {
      attemptCount++;
      try {
        final response = await _client
            .get(
              Uri.parse(url),
              headers: {
                ..._defaultHeaders,
                ...?headers,
                ...?requestConfig?.headers,
              },
            )
            .timeout(timeout ?? const Duration(seconds: 30));

        final rawData = _parseResponseBody(response);

        // First process via basic response data handling
        var processedData = _processResponseData(rawData, requestConfig);

        // Then apply custom transformer if available
        if (requestConfig != null) {
          processedData = requestConfig.transformResponse(processedData);
        }

        return NetworkResponse(
          statusCode: response.statusCode,
          data: processedData,
          headers: response.headers,
        );
      } catch (e) {
        // If we have retries left and this is a retryable error, try again
        if (attemptCount < maxAttempts) {
          continue;
        }
        // Otherwise, rethrow
        rethrow;
      }
    }
  }

  /// Sends a POST request to the specified endpoint
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [body]: Optional request body as a map
  /// - [headers]: Optional headers to include in the request
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns a [NetworkResponse] with the result of the request
  @override
  Future<NetworkResponse> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) async {
    final url = requestConfig?.url ?? _buildUrl(endpoint);
    final processedBody = _processRequestBody(body, requestConfig);
    final bodyJson =
        processedBody != null
            ? jsonEncode(_encryptIfEnabled(processedBody))
            : null;

    final response = await _client.post(
      Uri.parse(url),
      headers: {..._defaultHeaders, ...?headers, ...?requestConfig?.headers},
      body: bodyJson,
    );

    final rawData = _parseResponseBody(response);
    final data = _processResponseData(rawData, requestConfig);

    return NetworkResponse(
      statusCode: response.statusCode,
      data: data,
      headers: response.headers,
    );
  }

  /// Sends a PUT request to the specified endpoint
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [body]: Optional request body as a map
  /// - [headers]: Optional headers to include in the request
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns a [NetworkResponse] with the result of the request
  @override
  Future<NetworkResponse> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) async {
    final url = requestConfig?.url ?? _buildUrl(endpoint);
    final processedBody = _processRequestBody(body, requestConfig);
    final bodyJson =
        processedBody != null
            ? jsonEncode(_encryptIfEnabled(processedBody))
            : null;

    final response = await _client.put(
      Uri.parse(url),
      headers: {..._defaultHeaders, ...?headers, ...?requestConfig?.headers},
      body: bodyJson,
    );

    final rawData = _parseResponseBody(response);
    final data = _processResponseData(rawData, requestConfig);

    return NetworkResponse(
      statusCode: response.statusCode,
      data: data,
      headers: response.headers,
    );
  }

  /// Sends a PATCH request to the specified endpoint
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [body]: Optional request body as a map
  /// - [headers]: Optional headers to include in the request
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns a [NetworkResponse] with the result of the request
  @override
  Future<NetworkResponse> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) async {
    final url = requestConfig?.url ?? _buildUrl(endpoint);
    final processedBody = _processRequestBody(body, requestConfig);
    final bodyJson =
        processedBody != null
            ? jsonEncode(_encryptIfEnabled(processedBody))
            : null;

    final response = await _client.patch(
      Uri.parse(url),
      headers: {..._defaultHeaders, ...?headers, ...?requestConfig?.headers},
      body: bodyJson,
    );

    final rawData = _parseResponseBody(response);
    final data = _processResponseData(rawData, requestConfig);

    return NetworkResponse(
      statusCode: response.statusCode,
      data: data,
      headers: response.headers,
    );
  }

  /// Sends a DELETE request to the specified endpoint
  ///
  /// Parameters:
  /// - [endpoint]: The API endpoint
  /// - [headers]: Optional headers to include in the request
  /// - [requestConfig]: Optional custom request configuration
  ///
  /// Returns a [NetworkResponse] with the result of the request
  @override
  Future<NetworkResponse> delete(
    String endpoint, {
    Map<String, String>? headers,
    RestRequest? requestConfig,
  }) async {
    final url = requestConfig?.url ?? _buildUrl(endpoint);
    final response = await _client.delete(
      Uri.parse(url),
      headers: {..._defaultHeaders, ...?headers, ...?requestConfig?.headers},
    );

    final rawData = _parseResponseBody(response);
    final data = _processResponseData(rawData, requestConfig);

    return NetworkResponse(
      statusCode: response.statusCode,
      data: data,
      headers: response.headers,
    );
  }

  /// Parses the response body as JSON if possible
  ///
  /// Parameters:
  /// - [response]: The HTTP response
  ///
  /// Returns the parsed data or null if parsing failed
  dynamic _parseResponseBody(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      final jsonData = jsonDecode(response.body);

      // Apply decryption if needed
      if (jsonData is Map<String, dynamic> && _decryptionHandler != null) {
        return _decryptIfNeeded(jsonData);
      }
      return jsonData;
    } catch (e) {
      return response.body;
    }
  }

  /// Encrypts data if an encryption handler is set
  ///
  /// [data] The data to encrypt
  /// Returns the encrypted data or original data if no handler is set
  Map<String, dynamic> _encryptIfEnabled(Map<String, dynamic> data) {
    if (_encryptionHandler != null) {
      return _encryptionHandler!(data);
    }
    return data;
  }

  /// Decrypts data if a decryption handler is set
  ///
  /// [data] The data to decrypt
  /// Returns the decrypted data or original data if no handler is set
  Map<String, dynamic> _decryptIfNeeded(Map<String, dynamic> data) {
    if (_decryptionHandler != null) {
      return _decryptionHandler!(data);
    }
    return data;
  }
}
