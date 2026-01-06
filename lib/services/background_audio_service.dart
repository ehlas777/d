import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Background audio service for TTS playback
/// Enables audio to continue playing when app is backgrounded or screen is locked
class BackgroundAudioService {
  static BackgroundAudioService? _instance;
  AudioHandler? _audioHandler;
  AudioPlayer? _player;

  BackgroundAudioService._();

  static BackgroundAudioService get instance {
    _instance ??= BackgroundAudioService._();
    return _instance!;
  }

  /// Initialize the background audio service
  Future<void> initialize() async {
    if (_audioHandler != null) return;

    _audioHandler = await AudioService.init(
      builder: () => PolyDubAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.polydub.audio',
        androidNotificationChannelName: 'PolyDub Audio Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    );
  }

  /// Play audio file
  Future<void> play(File audioFile) async {
    if (_audioHandler == null) {
      await initialize();
    }

    final handler = _audioHandler as PolyDubAudioHandler;
    await handler.playFile(audioFile);
  }

  /// Stop playback
  Future<void> stop() async {
    final handler = _audioHandler as PolyDubAudioHandler?;
    await handler?.stop();
  }

  /// Pause playback
  Future<void> pause() async {
    final handler = _audioHandler as PolyDubAudioHandler?;
    await handler?.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    final handler = _audioHandler as PolyDubAudioHandler?;
    await handler?.play();
  }

  /// Check if currently playing
  bool get isPlaying {
    final handler = _audioHandler as PolyDubAudioHandler?;
    return handler?.playbackState.value.playing ?? false;
  }

  /// Dispose resources
  Future<void> dispose() async {
    final handler = _audioHandler as PolyDubAudioHandler?;
    await handler?.stop();
    _player?.dispose();
    _player = null;
  }
}

/// Audio handler implementation for background playback
class PolyDubAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  PolyDubAudioHandler() {
    // Listen to player state changes
    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        playing: _player.playing,
        processingState: _mapProcessingState(event.processingState),
      ));
    });

    // Listen to player completion
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        stop();
      }
    });
  }

  /// Play audio file
  Future<void> playFile(File audioFile) async {
    try {
      // Set media item for lock screen display
      mediaItem.add(MediaItem(
        id: audioFile.path,
        title: 'PolyDub Translation Audio',
        artist: 'PolyDub',
        artUri: Uri.parse('asset:///assets/images/logo.png'),
      ));

      // Load and play audio
      await _player.setFilePath(audioFile.path);
      await _player.play();

      // Update playback state
      playbackState.add(playbackState.value.copyWith(
        playing: true,
        controls: [
          MediaControl.pause,
          MediaControl.stop,
        ],
        processingState: AudioProcessingState.ready,
      ));
    } catch (e) {
      print('Error playing audio: $e');
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.error,
      ));
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Map just_audio ProcessingState to audio_service AudioProcessingState
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Save state when app is force-closed
    await stop();
    await super.onTaskRemoved();
  }
}
