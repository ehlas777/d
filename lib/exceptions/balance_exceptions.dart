/// Balance-related exceptions for usage limits
class InsufficientBalanceException implements Exception {
  final double required;
  final double available;
  final double shortfall;
  
  InsufficientBalanceException({
    required this.required,
    required this.available,
  }) : shortfall = required - available;
  
  @override
  String toString() => 
    'Жеткіліксіз баланс: ${required.toStringAsFixed(1)} мин керек, '
    '${available.toStringAsFixed(1)} мин бар. '
    'Жетіспейді: ${shortfall.toStringAsFixed(1)} мин';
}

/// Video duration exceeds subscription tier limit
class VideoTooLongException implements Exception {
  final double videoDuration;
  final double maxAllowed;
  
  VideoTooLongException({
    required this.videoDuration,
    required this.maxAllowed,
  });
  
  @override
  String toString() => 
    'Видео тым ұзын: ${videoDuration.toStringAsFixed(1)} мин, '
    'максимум: ${maxAllowed.toStringAsFixed(1)} мин';
}

/// Idempotency key conflict - request is already processing
class IdempotencyConflictException implements Exception {
  final String idempotencyKey;
  final String? message;
  
  IdempotencyConflictException({
    required this.idempotencyKey,
    this.message,
  });
  
  @override
  String toString() => 
    'Сұрау өңделуде (idempotency conflict): $idempotencyKey${message != null ? " - $message" : ""}';
}
