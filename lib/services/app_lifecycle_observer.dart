import 'package:flutter/widgets.dart';

/// Observes app lifecycle state changes
/// Notifies when app goes to background or returns to foreground
class AppLifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState state)? onLifecycleChanged;

  AppLifecycleObserver({this.onLifecycleChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 App lifecycle changed: $state');
    onLifecycleChanged?.call(state);
  }

  /// Attach observer to Flutter binding
  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Detach observer from Flutter binding
  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
