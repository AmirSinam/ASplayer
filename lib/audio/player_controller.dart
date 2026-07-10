import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library_store.dart';
import '../data/widget_bridge.dart';
import '../models.dart';

/// Owns playback and the queue. The audio_service handler below is a thin shell
/// that forwards notification / headphone commands here.
class PlayerController extends ChangeNotifier {
  PlayerController(this.store) {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _advance(auto: true);
      }
      _publish();
      notifyListeners();
    });
  }

  final LibraryStore store;
  final AudioPlayer _player = AudioPlayer();

  ASAudioHandler? _handler;
  void attach(ASAudioHandler handler) => _handler = handler;

  Track? _current;
  List<Track> _queue = [];
  List<Track> _original = [];
  bool _shuffle = false;
  Repeat _repeat = Repeat.off;
  double _speed = 1;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;

  Track? get current => _current;
  bool get playing => _player.playing;
  List<Track> get queue => List.unmodifiable(_queue);
  bool get shuffle => _shuffle;
  Repeat get repeat => _repeat;
  double get speed => _speed;
  double get volume => _player.volume;
  Duration? get sleepRemaining => _sleepRemaining;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get duration => _player.duration ?? _current?.duration ?? Duration.zero;

  /// Derived rather than stored, so queue edits can never desync it.
  int get _index {
    if (_current == null) return 0;
    final i = _queue.indexWhere((t) => t.id == _current!.id);
    return i < 0 ? 0 : i;
  }

  List<Track> get upNext {
    final next = _index + 1;
    if (next >= _queue.length) return const [];
    return _queue.sublist(next);
  }

  // MARK: - Transport

  Future<void> play(Track track, List<Track> tracks) async {
    _original = [...tracks];
    _queue = [...tracks];
    if (_shuffle) _reshuffle(keeping: track);
    await _load(track);
    await resume();
  }

  Future<void> toggle() => playing ? pause() : resume();

  Future<void> resume() async {
    await _player.setSpeed(_speed);
    await _player.play();
  }

  Future<void> pause() => _player.pause();

  Future<void> next() => _advance(auto: false);

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // Standard behaviour: restart the track unless we're near the beginning.
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final target = (_index - 1 + _queue.length) % _queue.length;
    await _load(_queue[target]);
    await resume();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _publish();
  }

  Future<void> seekToFraction(double fraction) =>
      seek(duration * fraction.clamp(0.0, 1.0));

  Future<void> setSpeed(double value) async {
    _speed = value;
    await _player.setSpeed(value);
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    await _player.setVolume(value.clamp(0.0, 1.0));
    notifyListeners();
  }

  // MARK: - Queue editing

  Future<void> addToQueue(Track track) async {
    _queue.add(track);
    _original = [..._queue];
    notifyListeners();
  }

  Future<void> playNext(Track track) async {
    _queue.insert(min(_index + 1, _queue.length), track);
    _original = [..._queue];
    notifyListeners();
  }

  Future<void> playFromQueue(Track track) async {
    if (!_queue.any((t) => t.id == track.id)) return;
    await _load(track);
    await resume();
  }

  void moveUpNext(int oldIndex, int newIndex) {
    final base = _index + 1;
    final track = _queue.removeAt(base + oldIndex);
    _queue.insert(base + (newIndex > oldIndex ? newIndex - 1 : newIndex), track);
    _original = [..._queue];
    notifyListeners();
  }

  void removeUpNext(int offset) {
    _queue.removeAt(_index + 1 + offset);
    _original = [..._queue];
    notifyListeners();
  }

  // MARK: - Shuffle & repeat

  void toggleShuffle() {
    _shuffle = !_shuffle;
    final track = _current;
    if (track != null) {
      if (_shuffle) {
        _reshuffle(keeping: track);
      } else {
        _queue = [..._original];
      }
    }
    notifyListeners();
  }

  void cycleRepeat() {
    _repeat = switch (_repeat) {
      Repeat.off => Repeat.all,
      Repeat.all => Repeat.one,
      Repeat.one => Repeat.off,
    };
    notifyListeners();
  }

  void _reshuffle({required Track keeping}) {
    final rest = _original.where((t) => t.id != keeping.id).toList()..shuffle();
    _queue = [keeping, ...rest];
  }

  // MARK: - Sleep timer

  void startSleepTimer(int minutes) {
    cancelSleepTimer();
    final end = DateTime.now().add(Duration(minutes: minutes));
    _sleepRemaining = end.difference(DateTime.now());

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = end.difference(DateTime.now());
      if (left.isNegative || left.inSeconds <= 0) {
        pause();
        cancelSleepTimer();
      } else {
        _sleepRemaining = left;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = null;
    notifyListeners();
  }

  // MARK: - Internals

  /// [auto] means playback reached the end of a track on its own, which is the
  /// only case where repeat mode has a say.
  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;

    if (auto && _repeat == Repeat.one) {
      await seek(Duration.zero);
      await resume();
      return;
    }

    final isLast = _index == _queue.length - 1;
    if (auto && isLast && _repeat == Repeat.off) {
      await pause();
      await seek(Duration.zero);
      return;
    }

    await _load(_queue[(_index + 1) % _queue.length]);
    await resume();
  }

  Future<void> _load(Track track) async {
    _current = track;
    try {
      await _player.setFilePath(store.filePathOf(track));
    } catch (_) {
      _current = null;
      notifyListeners();
      return;
    }

    // Tag duration is often wrong or missing; trust the decoder.
    final decoded = _player.duration;
    if (decoded != null && (track.durationMs - decoded.inMilliseconds).abs() > 1000) {
      track.durationMs = decoded.inMilliseconds;
    }

    await store.markPlayed(track);
    _publish();
    notifyListeners();
  }

  void _publish() {
    final handler = _handler;
    final track = _current;
    if (handler == null || track == null) return;

    final cover = store.coverPathOf(track);

    // Keep the home-screen widget in step with the notification.
    WidgetBridge.update(
      title: track.title,
      artist: track.artist,
      coverPath: cover,
      playing: playing,
    );

    handler.mediaItem.add(MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist.isEmpty ? null : track.artist,
      album: track.album.isEmpty ? null : track.album,
      duration: duration,
      artUri: cover == null ? null : Uri.file(cover),
    ));

    handler.playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      speed: _speed,
    ));
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }
}

class ASAudioHandler extends BaseAudioHandler with SeekHandler {
  ASAudioHandler(this.controller);

  final PlayerController controller;

  @override
  Future<void> play() => controller.resume();

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> skipToNext() => controller.next();

  @override
  Future<void> skipToPrevious() => controller.previous();

  @override
  Future<void> seek(Duration position) => controller.seek(position);

  @override
  Future<void> stop() => controller.pause();
}
