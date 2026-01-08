import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network resilience handler for robust error recovery
/// Handles network failures, retries with exponential backoff, and connectivity monitoring
class NetworkResilienceHandler {
  final Connectivity _connectivity = Connectivity();
  
  /// Check if device has network connectivity
  Future<bool> hasNetwork() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      
      // Check if we have any connectivity (wifi, mobile, etc.)
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }
      
      // Additional check: try to lookup a reliable host
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 5));
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    } catch (e) {
      print('⚠️ Network check failed: $e');
      return false;
    }
  }

  /// Retry an operation with exponential backoff
  /// Useful for transient network failures
  Future<T> retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxRetries = 5,
    Duration initialDelay = const Duration(seconds: 2),
    bool checkNetwork = true,
    List<Duration>? customDelays,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempt = 0;
    // If custom delays provided, use them. Otherwise generate exponential backoff.
    // If customDelays is used, maxRetries is ignored (length of list used)
    final effectiveMaxRetries = customDelays?.length ?? maxRetries;
    Duration currentDelay = initialDelay;

    while (attempt < maxRetries) {
      try {
        // Check network connectivity before attempting
        if (checkNetwork && !await hasNetwork()) {
          throw NetworkException('No internet connection');
        }

        // Attempt the operation
        return await operation();
      } catch (e) {
        attempt++;
        
        if (attempt >= effectiveMaxRetries) {
          print('❌ Max retries ($effectiveMaxRetries) exceeded');
          rethrow;
        }

        // Custom retry predicate
        if (shouldRetry != null && !shouldRetry(e)) {
           print('⛔ Error not retriable according to predicate: $e');
           rethrow;
        }

        // Log the retry
        print('⚠️ Attempt $attempt/$maxRetries failed: $e');
        print('⏳ Retrying in ${currentDelay.inSeconds}s...');

        // Wait before retrying
        await Future.delayed(currentDelay);

        // Determine delay
        if (customDelays != null) {
          // Use specific delay for this attempt (attempt is now 1-based index effectively for previous failure)
          // attempt was incremented, so retry #1 uses index 0
          if (attempt - 1 < customDelays.length) {
             currentDelay = customDelays[attempt - 1];
          }
        } else {
          // Exponential backoff: double the delay each time
          currentDelay = currentDelay * 2;
          
          // Cap at 60 seconds
          if (currentDelay > const Duration(seconds: 60)) {
            currentDelay = const Duration(seconds: 60);
          }
        }
      }
    }

    // Should never reach here, but Dart requires a return
    throw Exception('Retry logic failed unexpectedly');
  }

  /// Wait for network to become available
  /// Returns true if network is available, false if timeout
  Future<bool> waitForNetwork({
    Duration timeout = const Duration(minutes: 5),
    Duration checkInterval = const Duration(seconds: 5),
  }) async {
    final startTime = DateTime.now();
    
    print('⏳ Waiting for network connection...');
    
    while (DateTime.now().difference(startTime) < timeout) {
      if (await hasNetwork()) {
        print('✅ Network connection restored');
        return true;
      }
      
      await Future.delayed(checkInterval);
    }
    
    print('❌ Network wait timeout');
    return false;
  }

  /// Listen to network connectivity changes
  Stream<bool> watchConnectivity() async* {
    yield await hasNetwork(); // Initial state
    
    await for (final result in _connectivity.onConnectivityChanged) {
      // When connectivity changes, check actual internet access
      final hasInternet = await hasNetwork();
      yield hasInternet;
    }
  }

  /// Check if an error is network-related and retriable
  bool isNetworkError(dynamic error) {
    if (error is SocketException) return true;
    if (error is NetworkException) return true;
    if (error is TimeoutException) return true;
    
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout');
  }
}

/// Custom exception for network-related errors
class NetworkException implements Exception {
  final String message;
  
  NetworkException(this.message);
  
  @override
  String toString() => 'NetworkException: $message';
}
