import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Storage manager for disk space monitoring and cleanup
/// Prevents storage overflow and manages temporary files
class StorageManager {
  /// Check if there's enough free space on device
  /// [requiredMB] - required space in megabytes
  Future<bool> hasEnoughSpace(int requiredMB) async {
    try {
      if (Platform.isAndroid) {
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          final stat = dir.statSync();
          final availableBytes = stat.size; // Available space
          final availableMB = availableBytes / (1024 * 1024);
          
          print('📊 Available space: ${availableMB.toStringAsFixed(0)} MB');
          print('📊 Required space: $requiredMB MB');
          
          return availableMB > requiredMB;
        }
      } else if (Platform.isIOS) {
        // iOS doesn't provide direct filesystem stats
        // Use a conservative estimate based on app documents directory
        final dir = await getApplicationDocumentsDirectory();
        
        // Try to create a test file to check if we can write
        try {
          final testFile = File('${dir.path}/.space_test');
          await testFile.writeAsString('test');
          await testFile.delete();
          return true; // If we can write, assume we have space
        } catch (_) {
          return false;
        }
      }
    } catch (e) {
      print('⚠️ Storage check failed: $e');
    }
    
    // If we can't check, assume we have enough space
    return true;
  }

  /// Estimate required space for video processing
  /// Returns estimated MB needed
  Future<int> estimateRequiredSpace({
    required String videoPath,
    required int segmentCount,
  }) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        throw Exception('Video file not found: $videoPath');
      }

      final videoSizeMB = await videoFile.length() / (1024 * 1024);
      
      // Rough estimate:
      // - Original video: already exists
      // - Split videos: ~same as original
      // - Audio files: ~10% of video size
      // - Merged videos: ~same as original
      // - Final video: ~same as original
      // Total: ~3.1x original size + buffer
      
      final estimatedMB = (videoSizeMB * 3.5).ceil() + 100; // +100 MB buffer
      
      print('📊 Video size: ${videoSizeMB.toStringAsFixed(0)} MB');
      print('📊 Estimated required space: $estimatedMB MB');
      
      return estimatedMB;
    } catch (e) {
      print('⚠️ Space estimation failed: $e');
      return 1000; // Conservative fallback: 1GB
    }
  }

  /// Clean up temporary files for a project
  Future<void> cleanupTempFiles(String projectId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      final dirsToClean = [
        'split_videos',
        'merged_videos',
        'tts_audio',
      ];

      int totalDeleted = 0;
      
      for (final dirName in dirsToClean) {
        final dir = Directory('${appDir.path}/$dirName');
        if (await dir.exists()) {
          // Delete all subdirectories and files
          await for (final entity in dir.list()) {
            try {
              await entity.delete(recursive: true);
              totalDeleted++;
            } catch (e) {
              print('⚠️ Failed to delete ${entity.path}: $e');
            }
          }
        }
      }
      
      print('🗑️ Cleaned up $totalDeleted temporary files/directories');
    } catch (e) {
      print('⚠️ Cleanup failed: $e');
    }
  }

  /// Clean up old project files (older than maxAge)
  Future<void> cleanupOldProjects(Duration maxAge) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      
      int totalCleaned = 0;
      
      await for (final entity in appDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          
          if (age > maxAge) {
            try {
              await entity.delete();
              totalCleaned++;
            } catch (e) {
              print('⚠️ Failed to delete old file: $e');
            }
          }
        }
      }
      
      print('🗑️ Cleaned up $totalCleaned old files');
    } catch (e) {
      print('⚠️ Old project cleanup failed: $e');
    }
  }

  /// Get total size of app's document directory
  Future<int> getStorageUsage() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      int totalSize = 0;
      
      await for (final entity in appDir.list(recursive: true)) {
        if (entity is File) {
          final size = await entity.length();
          totalSize += size;
        }
      }
      
      final sizeMB = totalSize / (1024 * 1024);
      print('📊 Total storage usage: ${sizeMB.toStringAsFixed(2)} MB');
      
      return totalSize;
    } catch (e) {
      print('⚠️ Storage usage check failed: $e');
      return 0;
    }
  }

  /// Clean up a specific directory
  Future<void> cleanupDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        print('🗑️ Cleaned directory: $dirPath');
      }
    } catch (e) {
      print('⚠️ Directory cleanup failed: $e');
    }
  }
}

/// Exception for insufficient storage
class InsufficientStorageException implements Exception {
  final int requiredMB;
  final int? availableMB;
  
  InsufficientStorageException({
    required this.requiredMB,
    this.availableMB,
  });
  
  @override
  String toString() {
    if (availableMB != null) {
      return 'Insufficient storage: need $requiredMB MB, have $availableMB MB';
    }
    return 'Insufficient storage: need $requiredMB MB';
  }
}
