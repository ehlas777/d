import 'dart:async';

/// Throttled queue for rate limiting API requests
/// Prevents overwhelming the server with too many concurrent requests
class ThrottledQueue {
  final int maxConcurrent;
  final Duration delayBetweenRequests;
  
  int _activeRequests = 0;
  final List<Completer<void>> _waitingQueue = [];

  ThrottledQueue({
    this.maxConcurrent = 3,
    this.delayBetweenRequests = const Duration(milliseconds: 500),
  });

  /// Add a task to the queue
  /// Will wait until there's capacity and delay has passed
  Future<T> add<T>(Future<T> Function() task) async {
    // Wait until we have capacity
    while (_activeRequests >= maxConcurrent) {
      final completer = Completer<void>();
      _waitingQueue.add(completer);
      await completer.future;
    }

    _activeRequests++;
    
    try {
      // Add delay between requests
      if (delayBetweenRequests > Duration.zero) {
        await Future.delayed(delayBetweenRequests);
      }
      
      // Execute the task
      return await task();
    } finally {
      _activeRequests--;
      
      // Notify next waiting task
      if (_waitingQueue.isNotEmpty) {
        final next = _waitingQueue.removeAt(0);
        next.complete();
      }
    }
  }

  /// Get current number of active requests
  int get activeCount => _activeRequests;

  /// Get current number of waiting tasks
  int get queuedCount => _waitingQueue.length;

  /// Check if queue is at capacity
  bool get isFull => _activeRequests >= maxConcurrent;

  /// Clear all waiting tasks
  void clear() {
    for (final completer in _waitingQueue) {
      completer.completeError(Exception('Queue cleared'));
    }
    _waitingQueue.clear();
  }
}
