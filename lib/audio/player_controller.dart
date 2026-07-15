import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/device_music.dart';
import '../data/library_store.dart';
import '../data/widget_bridge.dart';
import '../models.dart';
import '../platform.dart';

/// Owns playback and the queue. The audio_service handler below is a thin shell
/// that forwards notification / headphone commands here.
class PlayerController extends ChangeNotifier {
  PlayerController(this.store) {
    // A listener on each player; only the active one drives state and advance.
    for (final p in _players) {
      p.playerStateStream.listen((state) {
        if (p != _player) return; // the fading-out player is ignored
        if (state.processingState == ProcessingState.completed) {
          _advance(auto: true);
        }
        _publish();
        notifyListeners();
      });
      p.positionStream.listen((pos) => _maybeCrossfade(p, pos));
    }
    _loadCrossfadePrefs();
    // Start the slider matching the phone's current media volume (Android).
    if (Plat.isAndroid) {
      DeviceMusic.getVolume().then((v) {
        _volume = v;
        notifyListeners();
      });
    }
  }

  final LibraryStore store;

  // Two players so the next track can fade in while the current one fades out.
  // The idle player stays paused and silent unless a crossfade is happening.
  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  int _active = 0;
  AudioPlayer get _player => _players[_active];
  AudioPlayer get _idle => _players[1 - _active];

  // Crossfade is off by default; when off, playback takes the exact same
  // single-player path it always did.
  bool _crossfade = false;
  int _crossfadeSeconds = 6;
  bool _fading = false;
  Timer? _fadeTimer;

  ASAudioHandler? _handler;
  void attach(ASAudioHandler handler) => _handler = handler;

  Track? _current;
  List<Track> _queue = [];
  List<Track> _original = [];
  bool _shuffle = false;
  Repeat _repeat = Repeat.off;
  double _speed = 1;
  // Mirrors the system media volume so the on-screen slider matches the
  // hardware buttons; the decoder itself always runs at full level.
  double _volume = 1;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;

  Track? get current => _current;
  bool get playing => _player.playing;
  List<Track> get queue => List.unmodifiable(_queue);
  bool get shuffle => _shuffle;
  Repeat get repeat => _repeat;
  double get speed => _speed;
  double get volume => _volume;
  bool get crossfade => _crossfade;
  int get crossfadeSeconds => _crossfadeSeconds;
  Duration? get sleepRemaining => _sleepRemaining;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
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
    _cancelFade();
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

  Future<void> pause() async {
    _cancelFade();
    await _player.pause();
  }

  Future<void> next() {
    // With crossfade on, slide into the next track instead of cutting to it.
    if (_crossfade && !_fading && _queue.isNotEmpty) {
      final target = _queue[(_index + 1) % _queue.length];
      if (target.id != _current?.id) return _crossfadeTo(target);
    }
    return _advance(auto: false);
  }

  Future<void> previous() async {
    _cancelFade();
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

  /// Re-reads the system volume — call when the player opens, in case the
  /// hardware buttons moved it while we weren't looking. (Android only.)
  Future<void> refreshVolume() async {
    if (!Plat.isAndroid) return;
    _volume = await DeviceMusic.getVolume();
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    // On Android the slider drives the system media volume; on desktop there is
    // no such channel, so we attenuate the player's own output instead.
    if (Plat.isAndroid) {
      await DeviceMusic.setVolume(_volume);
    } else {
      await _player.setVolume(_volume);
    }
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

  // MARK: - Crossfade

  Future<void> _loadCrossfadePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _crossfade = prefs.getBool('crossfade') ?? false;
    _crossfadeSeconds = prefs.getInt('crossfadeSeconds') ?? 6;
    notifyListeners();
  }

  Future<void> setCrossfade(bool enabled) async {
    _crossfade = enabled;
    if (!enabled) _cancelFade();
    (await SharedPreferences.getInstance()).setBool('crossfade', enabled);
    notifyListeners();
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    _crossfadeSeconds = seconds.clamp(2, 12);
    (await SharedPreferences.getInstance()).setInt('crossfadeSeconds', _crossfadeSeconds);
    notifyListeners();
  }

  /// On Android the player runs at full and the system controls loudness, so the
  /// resting level is 1. On desktop the player's own volume is the user's level.
  double get _restingVolume => Plat.isAndroid ? 1.0 : _volume;

  /// The track auto-play would move to next — or null when it would loop the
  /// same track or stop at the end. Used to decide whether an early crossfade
  /// makes sense.
  Track? _nextTrackForAuto() {
    if (_queue.isEmpty) return null;
    if (_repeat == Repeat.one) return null;
    final isLast = _index == _queue.length - 1;
    if (isLast && _repeat == Repeat.off) return null;
    return _queue[(_index + 1) % _queue.length];
  }

  /// Fired for every position tick of the active player: once the track is
  /// inside the crossfade window of its end, start sliding into the next one.
  void _maybeCrossfade(AudioPlayer p, Duration pos) {
    if (!_crossfade || _fading || p != _player) return;
    final total = _player.duration;
    if (total == null || total == Duration.zero) return;
    final window = Duration(seconds: _crossfadeSeconds);
    // Skip very short tracks, and don't trigger in the opening seconds.
    if (pos < window) return;
    final remaining = total - pos;
    if (remaining.isNegative || remaining > window) return;
    final target = _nextTrackForAuto();
    if (target == null || target.id == _current?.id) return;
    _crossfadeTo(target);
  }

  /// Loads [track] into the idle player, makes it the active one, then ramps the
  /// two volumes past each other over the crossfade window.
  Future<void> _crossfadeTo(Track track) async {
    _fading = true;
    final outgoing = _player;
    final incoming = _idle;
    try {
      await incoming.setFilePath(store.filePathOf(track));
    } catch (_) {
      _fading = false;
      return; // couldn't load; the outgoing track keeps playing as normal
    }
    await incoming.setSpeed(_speed);
    // Silence the incoming, start it, then silence it again. just_audio can
    // ignore a volume set before playback has actually begun (issue #439), which
    // otherwise makes the new track blast at full over the old one — the noise.
    await incoming.setVolume(0);
    await incoming.play();
    await incoming.setVolume(0);

    // The incoming track is now the one on screen and in the notification.
    _active = 1 - _active;
    _current = track;
    await store.markPlayed(track);
    _publish();
    notifyListeners();

    final rest = _restingVolume;
    const steps = 40;
    final stepMs = (_crossfadeSeconds * 1000 / steps).round().clamp(20, 400);
    var i = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) {
      i++;
      final f = (i / steps).clamp(0.0, 1.0);
      // Equal-power curve keeps the loudness steady through the blend.
      incoming.setVolume(sin(f * pi / 2) * rest);
      outgoing.setVolume(cos(f * pi / 2) * rest);
      if (i >= steps) {
        t.cancel();
        outgoing.pause();
        outgoing.seek(Duration.zero);
        outgoing.setVolume(rest); // reset so it is ready to be reused
        _fading = false;
      }
    });
  }

  /// Aborts a fade in progress: the active (incoming) track jumps to full and
  /// the other is silenced. Called before any hard track change.
  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (_fading) {
      final rest = _restingVolume;
      _player.setVolume(rest);
      _idle.pause();
      _idle.setVolume(rest);
      _fading = false;
    }
  }

  // MARK: - Internals

  /// [auto] means playback reached the end of a track on its own, which is the
  /// only case where repeat mode has a say.
  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;
    _cancelFade();

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

    // Keep the home-screen widget in step with the notification. (Android only.)
    if (Plat.isAndroid) {
      WidgetBridge.update(
        title: track.title,
        artist: track.artist,
        coverPath: cover,
        playing: playing,
      );
    }

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
    _fadeTimer?.cancel();
    for (final p in _players) {
      p.dispose();
    }
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
