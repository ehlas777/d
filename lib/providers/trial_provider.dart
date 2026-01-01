import 'package:flutter/foundation.dart';
import '../services/trial_api_service.dart';

class TrialProvider with ChangeNotifier {
  TrialCheckResponse? _trialStatus;
  bool _isLoading = false;
  String? _error;
  
  TrialCheckResponse? get trialStatus => _trialStatus;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get canUseTrial => _trialStatus?.canUseTrial ?? false;
  int get attemptsRemaining => _trialStatus?.attemptsRemaining ?? 0;
  int get maxVideoDuration => _trialStatus?.maxVideoDuration ?? 60;
  
  /// Trial статусын тексеру
  Future<void> checkTrialStatus() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _trialStatus = await TrialApiService.checkTrial();
    } catch (e) {
      _error = e.toString();
      print('Error checking trial status: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Trial-ды аяқтау
  Future<bool> completeTrial({
    String? videoFileName,
    int? durationSeconds,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await TrialApiService.completeTrial(
        videoFileName: videoFileName,
        durationSeconds: durationSeconds,
      );
      
      // Статусты жаңарту
      await checkTrialStatus();
      
      return response.success;
    } catch (e) {
      _error = e.toString();
      print('Error completing trial: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
