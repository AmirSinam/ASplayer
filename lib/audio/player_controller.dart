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
      p.positionStream.listen((pos) => _onDeckPosition(p, pos));
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
  // single-player path it always did. See the "Crossfade" section below for the
  // state machine that drives the blend.
  bool _crossfade = false;
  int _crossfadeSeconds = 6;

  _FadeState _fade = _FadeState.idle;
  Timer? _fadeTicker;
  Duration _fadeLength = Duration.zero; // how long this blend should take
  Duration _fadeElapsed = Duration.zero; // progress banked across pauses
  DateTime? _fadeAnchor; // wall-clock start of the current running span
  AudioPlayer? _fadeOut; // the deck fading out
  bool get crossfading => _fade != _FadeState.idle;

  // Surfaced for the on-screen mix transition. [fadeProgress] runs 0→1 across a
  // blend (frozen while paused); [fadingOutTrack] is the track leaving. The UI
  // listens to the notifier directly so only the transition repaints, not the
  // whole screen.
  final ValueNotifier<double> fadeProgress = ValueNotifier<double>(0);
  Track? _fadingOut;
  Track? get fadingOutTrack => _fadingOut;

  // The next track is loaded onto the idle deck a few seconds early so the blend
  // can start instantly instead of waiting on a file open.
  String? _preloadedId;
  bool _preloading = false;
  Future<void>? _preloadFuture;

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
    _endCrossfade();
    _original = [...tracks];
    _queue = [...tracks];
    if (_shuffle) _reshuffle(keeping: track);
    await _load(track);
    await resume();
  }

  Future<void> toggle() => playing ? pause() : resume();

  Future<void> resume() async {
    // Resuming mid-blend continues both decks and the ramp where it froze.
    if (_fade == _FadeState.paused) {
      _resumeCrossfade();
      return;
    }
    await _player.setSpeed(_speed);
    await _player.play();
  }

  Future<void> pause() async {
    if (crossfading) {
      _pauseCrossfade();
      return;
    }
    await _player.pause();
  }

  /// Manual skip is always an immediate cut — crossfade is reserved for the
  /// natural end of a track. Any blend in flight is finalised first.
  Future<void> next() {
    _endCrossfade();
    return _advance(auto: false);
  }

  Future<void> previous() async {
    _endCrossfade();
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
    // Seeking during a blend collapses it: the incoming track becomes the sole
    // track, then the seek applies to it.
    if (crossfading) _endCrossfade();
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
  //
  // Playback runs on two decks (_players). Normally only the active deck plays.
  // As the active track nears its end, the next track starts from 0 on the idle
  // deck and the two volumes cross over an equal-power curve; the old deck is
  // then stopped and the decks have effectively swapped. The ramp is driven from
  // the wall clock (not a step counter) so timer jitter or lag can never desync
  // it, and it can be frozen and resumed for pause/resume.
  //
  // States: idle (single deck) → running (both decks, ramping) → idle. A blend
  // can also be paused (frozen) or ended early (collapsed to the incoming deck).

  static const _fadeTick = Duration(milliseconds: 33); // ~30fps for a smooth ramp

  Future<void> _loadCrossfadePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _crossfade = prefs.getBool('crossfade') ?? false;
    _crossfadeSeconds = prefs.getInt('crossfadeSeconds') ?? 6;
    notifyListeners();
  }

  Future<void> setCrossfade(bool enabled) async {
    _crossfade = enabled;
    if (!enabled) _endCrossfade();
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
  /// same track or stop at the end (so no crossfade should start).
  Track? _nextTrackForAuto() {
    if (_queue.isEmpty) return null;
    if (_repeat == Repeat.one) return null;
    final isLast = _index == _queue.length - 1;
    if (isLast && _repeat == Repeat.off) return null;
    return _queue[(_index + 1) % _queue.length];
  }

  /// How long the blend should actually run for this track. Capped at ~45% of
  /// the track so short tracks still play, and so a crossfade duration longer
  /// than the track can never span the whole thing.
  Duration _effectiveFade(Duration total) {
    final want = Duration(seconds: _crossfadeSeconds);
    final cap = Duration(milliseconds: (total.inMilliseconds * 0.45).round());
    return want <= cap ? want : cap;
  }

  /// The active track's length. Trusts the decoder, but falls back to the tag
  /// duration — some formats report a null decoder duration, which used to stop
  /// the crossfade from ever triggering.
  Duration? _activeTotal() {
    final decoded = _player.duration;
    if (decoded != null && decoded > Duration.zero) return decoded;
    final tag = _current?.duration;
    return (tag != null && tag > Duration.zero) ? tag : null;
  }

  /// Every position tick of the active deck: pre-loads the next track ahead of
  /// time, then starts the blend once the track reaches its trigger point.
  void _onDeckPosition(AudioPlayer deck, Duration pos) {
    if (!_crossfade || deck != _player || _fade != _FadeState.idle) return;
    final total = _activeTotal();
    if (total == null) return;
    final fade = _effectiveFade(total);
    if (fade <= Duration.zero) return;

    _maybePreloadNext(pos, total, fade);

    if (pos < total - fade) return;
    final target = _nextTrackForAuto();
    if (target == null || target.id == _current?.id) return;
    _beginCrossfade(target, fade);
  }

  /// Opens the next track on the idle deck a little before the blend is due, so
  /// [_beginCrossfade] can start it instantly with no file-open delay.
  void _maybePreloadNext(Duration pos, Duration total, Duration fade) {
    if (_preloading) return;
    if (pos < total - fade - const Duration(seconds: 4)) return;
    final next = _nextTrackForAuto();
    if (next == null || next.id == _current?.id || next.id == _preloadedId) return;
    _preloading = true;
    final id = next.id;
    _preloadFuture = _idle.setFilePath(store.filePathOf(next)).then((_) async {
      // If a blend already claimed the deck, leave it alone — _beginCrossfade
      // will have loaded what it needs.
      if (_fade == _FadeState.idle) {
        await _idle.pause();
        _preloadedId = id;
      }
    }).catchError((Object _) {}).whenComplete(() {
      _preloading = false;
    });
  }

  /// Loads [track] from 0 on the idle deck, makes it the active/visible track,
  /// then starts the volume ramp. Fire-and-forget; re-entry is blocked because
  /// the state flips to running on the first (synchronous) line.
  Future<void> _beginCrossfade(Track track, Duration fade) async {
    _fade = _FadeState.running;
    final outgoing = _player;
    final incoming = _idle;
    final outgoingTrack = _current; // captured before _current becomes the next

    try {
      // If a pre-load is still in flight for this deck, let it finish first so
      // the same deck is never opened twice at once.
      if (_preloading && _preloadFuture != null) {
        try {
          await _preloadFuture;
        } catch (_) {}
      }
      // Skip the file open if this track was pre-loaded onto the idle deck.
      if (_preloadedId != track.id) {
        await incoming.setFilePath(store.filePathOf(track));
      }
      _preloadedId = null; // consumed
      await incoming.seek(Duration.zero); // always start the next track at 0
      await incoming.setSpeed(_speed);
      // Silence, start, silence again: just_audio can ignore a volume set before
      // playback has actually begun (issue #439), which would otherwise let the
      // new track blast at full over the old one.
      await incoming.setVolume(0);
      await incoming.play();
      await incoming.setVolume(0);
    } catch (_) {
      // Load/handshake failed, or we were interrupted: leave the outgoing track
      // playing and let its own completion advance normally.
      if (_fade == _FadeState.running && _fadeOut == null) _fade = _FadeState.idle;
      return;
    }

    // A pause/seek/skip during the awaits above will have reset the state; if so,
    // undo the half-started incoming deck and bail without swapping.
    if (_fade != _FadeState.running) {
      await incoming.pause();
      await incoming.seek(Duration.zero);
      await incoming.setVolume(_restingVolume);
      return;
    }

    _fadeOut = outgoing;
    _fadingOut = outgoingTrack;
    fadeProgress.value = 0;
    _active = 1 - _active; // incoming is now the active/visible track
    _current = track;
    await store.markPlayed(track);
    _publish();
    notifyListeners();

    _fadeLength = fade;
    _fadeElapsed = Duration.zero;
    _fadeAnchor = DateTime.now();
    _startFadeTicker();
  }

  void _startFadeTicker() {
    _fadeTicker?.cancel();
    _fadeTicker = Timer.periodic(_fadeTick, (_) => _onFadeTick());
  }

  /// One ramp step. Progress comes from the wall clock, so a late or coalesced
  /// timer callback simply reads a larger elapsed value and stays correct.
  void _onFadeTick() {
    final anchor = _fadeAnchor;
    if (anchor == null || _fade != _FadeState.running) return;
    final elapsed = _fadeElapsed + DateTime.now().difference(anchor);
    final t = _fadeLength.inMilliseconds == 0
        ? 1.0
        : (elapsed.inMilliseconds / _fadeLength.inMilliseconds).clamp(0.0, 1.0);
    final rest = _restingVolume;
    // Equal-power curve: perceived loudness stays steady through the blend.
    _player.setVolume(sin(t * pi / 2) * rest); // incoming (active)
    _fadeOut?.setVolume(cos(t * pi / 2) * rest); // outgoing
    fadeProgress.value = t; // drives the on-screen mix transition
    if (t >= 1.0) _endCrossfade();
  }

  /// Collapses any blend to the single active (incoming) deck at full volume and
  /// stops the other deck. Used both for the natural end of a blend and to abort
  /// one for a pause-less interruption (skip/seek/new queue). A no-op when idle.
  void _endCrossfade() {
    _fadeTicker?.cancel();
    _fadeTicker = null;
    final wasFading = crossfading;
    final out = _fadeOut;
    if (out != null) {
      out.pause();
      out.seek(Duration.zero);
      out.setVolume(_restingVolume); // reset so it is ready to be reused
    }
    if (wasFading) _player.setVolume(_restingVolume); // incoming to full
    _fadeOut = null;
    _fadingOut = null;
    _fadeAnchor = null;
    _fadeElapsed = Duration.zero;
    _fade = _FadeState.idle;
    fadeProgress.value = 0;
    if (wasFading) notifyListeners(); // let the screen drop the transition
  }

  /// Freezes a running blend: both decks pause and the ramp's progress is banked
  /// so [_resumeCrossfade] can pick up exactly where it left off.
  void _pauseCrossfade() {
    final anchor = _fadeAnchor;
    if (anchor != null) {
      _fadeElapsed += DateTime.now().difference(anchor);
      _fadeAnchor = null;
    }
    _fadeTicker?.cancel();
    _fadeTicker = null;
    _fade = _FadeState.paused;
    _player.pause();
    _fadeOut?.pause();
    notifyListeners();
  }

  void _resumeCrossfade() {
    _fadeAnchor = DateTime.now();
    _fade = _FadeState.running;
    _fadeOut?.play();
    _player.play();
    _startFadeTicker();
    notifyListeners();
  }

  // MARK: - Internals

  /// [auto] means playback reached the end of a track on its own, which is the
  /// only case where repeat mode has a say.
  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;
    _endCrossfade();

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
    // A hard track change invalidates any pre-load queued for the old position.
    _preloadedId = null;
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
    _fadeTicker?.cancel();
    fadeProgress.dispose();
    for (final p in _players) {
      p.dispose();
    }
    super.dispose();
  }
}

/// The crossfade state machine's phases. `idle` is normal single-deck playback;
/// `running` is an active blend; `paused` is a blend frozen mid-ramp.
enum _FadeState { idle, running, paused }

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
