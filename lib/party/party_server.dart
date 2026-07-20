import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../models.dart';

/// A tiny web server the host runs during a party. Guests scan a QR and open the
/// served page in any browser — no app, no account, no install.
///
/// The page offers two modes per guest device:
///   • Controller — add songs to the host's queue and control host playback
///     (play/pause/next). Audio plays on the host's speaker; nothing crosses
///     the wire but title/artist and control commands. Always available.
///   • Player — stream a song and play it on the guest's own device. This does
///     send the audio file over the local network, so it is gated behind
///     [allowStreaming] and is OFF by default. The host turns it on per party.
class PartyServer {
  PartyServer({required this.store, required this.player});

  final LibraryStore store;
  final PlayerController player;

  /// When false, `/api/stream` returns 403 and guests can only control. The host
  /// flips this from the party screen. Off by default on purpose: streaming the
  /// audio to another person's device is a share the user should opt into.
  bool allowStreaming = false;

  HttpServer? _server;
  String? url;
  int addedCount = 0;

  bool get running => _server != null;

  /// Starts the server and returns the join URL, or null if there is no usable
  /// local network address (no Wi‑Fi / hotspot).
  Future<String?> start() async {
    if (_server != null) return url;
    final ip = await _localIp();
    if (ip == null) return null;
    try {
      _server = await shelf_io.serve(_handle, InternetAddress.anyIPv4, 8080);
    } catch (_) {
      // Port busy — let the OS pick a free one.
      _server = await shelf_io.serve(_handle, InternetAddress.anyIPv4, 0);
    }
    url = 'http://$ip:${_server!.port}';
    return url;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    url = null;
  }

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  Map<String, dynamic> _brief(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'durationMs': t.durationMs,
      };

  Future<Response> _handle(Request req) async {
    final path = req.url.path;

    if (path.isEmpty || path == 'index.html') {
      return Response.ok(_guestPage, headers: {'content-type': 'text/html; charset=utf-8'});
    }

    // Whether this party lets guests play on their own device.
    if (path == 'api/config') {
      return Response.ok(jsonEncode({'allowStreaming': allowStreaming}), headers: _json);
    }

    // The host's library — metadata only, plus a file extension so the browser
    // can decide for itself whether it can play the format.
    if (path == 'api/tracks') {
      final data = store.tracks.map((t) {
        final m = _brief(t);
        m['ext'] = _extOf(store.filePathOf(t));
        return m;
      }).toList();
      return Response.ok(jsonEncode(data), headers: _json);
    }

    // Live host state so guests see what is playing, the progress, and queue.
    if (path == 'api/state') {
      final cur = player.current;
      return Response.ok(
        jsonEncode({
          'playing': player.playing,
          'current': cur == null ? null : _brief(cur),
          'positionMs': player.position.inMilliseconds,
          'durationMs': player.duration.inMilliseconds,
          'queue': player.upNext.map(_brief).toList(),
        }),
        headers: _json,
      );
    }

    // The app's own fonts, so the guest page renders in Vazirmatn / Unbounded
    // even with no internet — served straight from the bundled assets.
    if (path == 'fonts/vazirmatn' || path == 'fonts/unbounded') {
      final asset = path.endsWith('vazirmatn')
          ? 'assets/fonts/Vazirmatn.ttf'
          : 'assets/fonts/Unbounded.ttf';
      try {
        final data = await rootBundle.load(asset);
        return Response.ok(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          headers: {'content-type': 'font/ttf', 'cache-control': 'max-age=86400'},
        );
      } catch (_) {
        return Response.notFound('no font');
      }
    }

    // A track's cover art, so rows look like the app. Metadata-sized artwork,
    // never the audio. Falls back to a generated cover on the client when 404.
    if (path.startsWith('api/cover/') && req.method == 'GET') {
      final id = Uri.decodeComponent(path.substring('api/cover/'.length));
      final track = store.byId(id);
      final cover = track == null ? null : store.coverPathOf(track);
      if (cover == null) return Response.notFound('no cover');
      final file = File(cover);
      if (!await file.exists()) return Response.notFound('no cover');
      final bytes = await file.readAsBytes();
      final png = bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
      return Response.ok(
        bytes,
        headers: {
          'content-type': png ? 'image/png' : 'image/jpeg',
          'cache-control': 'max-age=3600',
        },
      );
    }

    if (path == 'api/add' && req.method == 'POST') {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final track = store.byId(body['id'] as String);
        if (track != null) {
          await player.partyAdd(track);
          addedCount++;
          return Response.ok(jsonEncode({'ok': true, 'title': track.title}), headers: _json);
        }
      } catch (_) {
        // fall through to 404
      }
      return Response.notFound(jsonEncode({'ok': false}));
    }

    // Controller: drive the host's own playback.
    if (path == 'api/control' && req.method == 'POST') {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        switch (body['action']) {
          case 'toggle':
            await player.toggle();
          case 'next':
            await player.next();
          case 'prev':
            await player.previous();
          default:
            return Response.notFound(jsonEncode({'ok': false}));
        }
        return Response.ok(jsonEncode({'ok': true, 'playing': player.playing}), headers: _json);
      } catch (_) {
        return Response.notFound(jsonEncode({'ok': false}));
      }
    }

    // Player: stream a file so the guest's own device can play it. Gated.
    if (path.startsWith('api/stream/') && req.method == 'GET') {
      final id = Uri.decodeComponent(path.substring('api/stream/'.length));
      return _stream(req, id);
    }

    return Response.notFound('not found');
  }

  /// Serves an audio file with HTTP range support, which Safari's <audio>
  /// element requires for playback and seeking.
  Future<Response> _stream(Request req, String id) async {
    if (!allowStreaming) return Response.forbidden('streaming disabled');
    final track = store.byId(id);
    if (track == null) return Response.notFound('no track');
    final file = File(store.filePathOf(track));
    if (!await file.exists()) return Response.notFound('no file');

    final total = await file.length();
    final ctype = _contentType(_extOf(file.path));
    final range = req.headers['range'];

    if (range == null || !range.startsWith('bytes=')) {
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': ctype,
          'accept-ranges': 'bytes',
          'content-length': '$total',
        },
      );
    }

    // Single range only: "bytes=start-end", either side optional.
    final spec = range.substring(6).split('-');
    var start = int.tryParse(spec[0]) ?? 0;
    var end = spec.length > 1 && spec[1].isNotEmpty
        ? (int.tryParse(spec[1]) ?? total - 1)
        : total - 1;
    if (start < 0) start = 0;
    if (end > total - 1) end = total - 1;
    if (start > end) {
      return Response(416, headers: {'content-range': 'bytes */$total'});
    }

    return Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        'content-type': ctype,
        'accept-ranges': 'bytes',
        'content-range': 'bytes $start-$end/$total',
        'content-length': '${end - start + 1}',
      },
    );
  }

  String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  String _contentType(String ext) => switch (ext) {
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'aac' => 'audio/aac',
        'wav' => 'audio/wav',
        'flac' => 'audio/flac',
        'ogg' || 'opus' => 'audio/ogg',
        _ => 'application/octet-stream',
      };

  Future<String?> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          if (_isPrivate(a.address)) return a.address;
        }
      }
      // Fallback: any non-loopback IPv4.
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      final second = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }
}

/// The self-contained page guests see. It mirrors the app's own look as closely
/// as a web page can: the real Vazirmatn / Unbounded fonts (served from the
/// bundle), the tiffany accent, frosted-glass surfaces, album art with the same
/// generated-cover fallback, and a mini player with a live progress bar. RTL,
/// light/dark aware, no build step, no external requests.
const _guestPage = r'''
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#080808">
<title>ASplayer · مهمانی</title>
<style>
  @font-face{font-family:'Vazirmatn';src:url('fonts/vazirmatn') format('truetype');font-weight:100 900;font-display:swap;}
  @font-face{font-family:'Unbounded';src:url('fonts/unbounded') format('truetype');font-weight:400 900;font-display:swap;}

  :root{
    --accent:#0ABAB5; --onAccent:#03211F;
    --bg:#080808; --text:#ffffff; --sub:rgba(255,255,255,.55);
    --g1:rgba(255,255,255,.15); --g2:rgba(255,255,255,.055);
    --rim:rgba(255,255,255,.20); --shadow:rgba(0,0,0,.5);
    --track:rgba(255,255,255,.12);
    --skel:rgba(255,255,255,.06); --skel2:rgba(255,255,255,.14);
  }
  @media (prefers-color-scheme: light){
    :root{
      --bg:#F2F4F4; --text:#0B1211; --sub:rgba(11,18,17,.52);
      --g1:rgba(255,255,255,.92); --g2:rgba(255,255,255,.62);
      --rim:rgba(255,255,255,.95); --shadow:rgba(11,18,17,.12);
      --track:rgba(11,18,17,.10);
      --skel:rgba(11,18,17,.05); --skel2:rgba(11,18,17,.12);
    }
  }

  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
  html,body{overflow-x:hidden;}
  body{
    margin:0; background:var(--bg); color:var(--text);
    font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,Tahoma,sans-serif;
    padding-bottom:180px; position:relative; min-height:100vh;
  }
  body::before{
    content:''; position:fixed; inset:0; z-index:0; pointer-events:none;
    background:radial-gradient(130% 60% at 50% -12%, rgba(10,186,181,.18), transparent 58%);
  }
  .glass{
    background:linear-gradient(135deg,var(--g1),var(--g2));
    border:.9px solid var(--rim);
    box-shadow:0 10px 22px var(--shadow);
    -webkit-backdrop-filter:blur(22px) saturate(1.4);
    backdrop-filter:blur(22px) saturate(1.4);
  }

  header{
    position:sticky; top:0; z-index:5; padding:16px 16px 13px; text-align:center;
    border-radius:0 0 24px 24px; border-top:none;
  }
  .mark{font-family:'Unbounded','Vazirmatn',sans-serif;font-weight:800;font-size:23px;letter-spacing:-.6px;line-height:1;}
  .mark i{color:var(--accent);font-style:normal;}
  .tag{margin:7px 0 0;color:var(--sub);font-size:12.5px;}

  .search{position:sticky;top:70px;z-index:4;padding:12px 14px 6px;}
  .search .wrap{position:relative;}
  .search svg{position:absolute;right:16px;top:50%;transform:translateY(-50%);width:18px;height:18px;opacity:.5;}
  #q{
    width:100%;padding:13px 44px 13px 18px;border-radius:999px;color:var(--text);
    font-size:15px;font-family:inherit;outline:none;
    background:linear-gradient(135deg,var(--g1),var(--g2));border:.9px solid var(--rim);
    -webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);
    transition:border-color .2s, box-shadow .2s;
  }
  #q::placeholder{color:var(--sub);}
  #q:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(10,186,181,.25);}

  ul{list-style:none;margin:0;padding:4px 10px 20px;position:relative;z-index:1;}
  li{display:flex;align-items:center;gap:12px;padding:8px 10px;border-radius:16px;transition:background .15s;}
  li.on{background:linear-gradient(135deg,rgba(10,186,181,.14),rgba(10,186,181,.05));}
  li:active{background:var(--track);}

  .cover{position:relative;flex:none;border-radius:13px;overflow:hidden;display:flex;align-items:center;justify-content:center;}
  .cover .mono{color:rgba(255,255,255,.92);font-weight:800;line-height:1;font-family:'Unbounded','Vazirmatn',sans-serif;}
  .cover .blob{position:absolute;width:70%;height:70%;top:-14%;left:44%;border-radius:50%;background:rgba(255,255,255,.07);}
  .cover img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block;}

  .meta{min-width:0;flex:1;}
  .meta b{display:block;font-size:15.5px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  .meta small{display:block;margin-top:3px;font-size:12.5px;color:var(--sub);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  li.on .meta b{color:var(--accent);}

  .actions{flex:none;display:flex;align-items:center;gap:7px;}
  .btn-add{border:none;background:var(--accent);color:var(--onAccent);font-weight:700;font-family:inherit;
    padding:9px 16px;border-radius:999px;font-size:13px;box-shadow:0 4px 14px rgba(10,186,181,.32);}
  .btn-listen{width:42px;height:38px;border-radius:999px;border:1.4px solid var(--accent);background:transparent;
    color:var(--accent);font-size:14px;display:flex;align-items:center;justify-content:center;}
  button{cursor:pointer;} button:disabled{opacity:.55;}

  /* loading skeletons */
  #skeleton{padding:4px 10px;position:relative;z-index:1;}
  .skrow{display:flex;gap:12px;align-items:center;padding:8px 10px;}
  .sk{background:linear-gradient(90deg,var(--skel),var(--skel2),var(--skel));background-size:200% 100%;
    animation:sh 1.3s ease-in-out infinite;border-radius:8px;}
  .sk.cov{width:52px;height:52px;border-radius:13px;flex:none;}
  .sk.l1{height:13px;width:58%;} .sk.l2{height:11px;width:34%;margin-top:8px;}
  @keyframes sh{0%{background-position:200% 0}100%{background-position:-200% 0}}

  #empty{display:none;color:var(--sub);text-align:center;padding:48px 24px;position:relative;z-index:1;}
  #empty .note{font-size:34px;opacity:.5;}
  #empty p{margin:12px 0 0;font-size:14px;}

  /* bottom dock: host + local bars */
  #dock{position:fixed;left:0;right:0;bottom:0;z-index:6;padding:0 12px calc(12px + env(safe-area-inset-bottom));
    display:flex;flex-direction:column;gap:8px;pointer-events:none;}
  .bar{pointer-events:auto;display:none;align-items:center;gap:11px;padding:10px 12px;border-radius:22px;position:relative;overflow:hidden;}
  .bar.local{border-color:var(--accent);}
  .bar .cover{width:44px;height:44px;border-radius:11px;}
  .bar .meta b{font-size:14px;} .bar .meta small{font-size:11px;}
  .bar .meta small.here{color:var(--accent);}
  .cbtn{flex:none;border:none;width:40px;height:40px;border-radius:50%;background:var(--track);color:var(--text);
    font-size:17px;display:flex;align-items:center;justify-content:center;}
  .cbtn.main{background:var(--accent);color:var(--onAccent);box-shadow:0 4px 14px rgba(10,186,181,.32);}
  .cbtn.sm{width:34px;height:34px;font-size:14px;}
  .progress{position:absolute;left:0;right:0;bottom:0;height:3px;background:var(--track);}
  .progress i{display:block;height:100%;width:0%;background:var(--accent);border-radius:0 2px 2px 0;transition:width .28s linear;}

  #toast{position:fixed;left:50%;bottom:200px;transform:translateX(-50%) translateY(10px);z-index:9;
    background:var(--accent);color:var(--onAccent);padding:11px 22px;border-radius:999px;font-weight:700;font-size:13.5px;
    opacity:0;pointer-events:none;transition:.3s;box-shadow:0 10px 26px rgba(10,186,181,.45);}
  #toast.show{opacity:1;transform:translateX(-50%) translateY(0);}
</style>
</head>
<body>
<header class="glass">
  <div class="mark"><i>AS</i>player</div>
  <p class="tag" id="tag">آهنگ به صف اضافه کن · پخشِ میزبان رو کنترل کن</p>
</header>

<div class="search"><div class="wrap">
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
  <input id="q" placeholder="جست‌وجوی آهنگ...">
</div></div>

<div id="skeleton"></div>
<ul id="list"></ul>
<div id="empty"><div class="note">♪</div><p id="emptyMsg">آهنگی نیست</p></div>

<div id="dock">
  <div id="hostbar" class="bar glass">
    <div class="cover" id="hbCover"></div>
    <div class="meta"><b id="hbTitle">—</b><small>پخش روی میزبان</small></div>
    <button id="hbToggle" class="cbtn">⏸</button>
    <button id="hbNext" class="cbtn main">⏭</button>
    <div class="progress"><i id="hbBar"></i></div>
  </div>
  <div id="localbar" class="bar glass local">
    <button id="lbToggle" class="cbtn main">⏸</button>
    <div class="meta"><b id="lbTitle">—</b><small class="here">پخش روی این دستگاه</small></div>
    <div class="cover" id="lbCover"></div>
    <button id="lbClose" class="cbtn sm">✕</button>
  </div>
</div>
<audio id="audio" preload="none"></audio>
<div id="toast"></div>

<script>
var all=[], allowStream=false;
var $=function(id){return document.getElementById(id);};
var list=$('list'), q=$('q'), toast=$('toast'), empty=$('empty'), emptyMsg=$('emptyMsg'),
    skeleton=$('skeleton'), audio=$('audio'),
    hostbar=$('hostbar'), hbTitle=$('hbTitle'), hbToggle=$('hbToggle'), hbNext=$('hbNext'),
    hbBar=$('hbBar'), hbCover=$('hbCover'),
    localbar=$('localbar'), lbTitle=$('lbTitle'), lbToggle=$('lbToggle'), lbClose=$('lbClose'), lbCover=$('lbCover');

/* ---- generated cover, mirroring the app's DynamicCover ---- */
function hueOf(seed){var h=0;seed=String(seed||'');for(var i=0;i<seed.length;i++){h=(h*31+seed.charCodeAt(i))>>>0;}return h%360;}
function coverCss(seed){var h=hueOf(seed);return 'linear-gradient(135deg,hsl('+((h+24)%360)+',50%,50%),hsl('+h+',42%,26%))';}
function initial(seed){seed=(seed||'').trim();return seed?seed[0].toUpperCase():'♪';}
function fillCover(el,t,size){
  var seed=(t.artist||t.title||'♪');
  el.innerHTML='';
  el.style.background=coverCss(seed);
  var blob=document.createElement('div');blob.className='blob';el.appendChild(blob);
  var mono=document.createElement('span');mono.className='mono';mono.textContent=initial(seed);
  mono.style.fontSize=Math.round(size*0.42)+'px';el.appendChild(mono);
  var img=document.createElement('img');img.loading='lazy';img.decoding='async';
  img.onerror=function(){img.remove();};
  img.src='api/cover/'+encodeURIComponent(t.id);
  el.appendChild(img);
}

/* ---- format support (browser decides) ---- */
function mimeFor(ext){return {mp3:'audio/mpeg',m4a:'audio/mp4',aac:'audio/aac',wav:'audio/wav',flac:'audio/flac',ogg:'audio/ogg',opus:'audio/ogg'}[ext]||'';}
function canPlay(ext){var m=mimeFor(ext);if(!m)return false;try{return audio.canPlayType(m)!=='';}catch(e){return false;}}

function showToast(m){toast.textContent=m;toast.classList.add('show');clearTimeout(showToast._t);showToast._t=setTimeout(function(){toast.classList.remove('show');},1600);}

/* ---- list ---- */
function render(items){
  list.innerHTML='';
  empty.style.display=items.length?'none':'block';
  items.slice(0,400).forEach(function(t){
    var li=document.createElement('li');
    var cov=document.createElement('div');cov.className='cover';cov.style.width=cov.style.height='52px';
    fillCover(cov,t,52);

    var m=document.createElement('div');m.className='meta';
    var b=document.createElement('b');b.textContent=t.title||'—';
    var s=document.createElement('small');s.textContent=t.artist||'';
    m.appendChild(b);m.appendChild(s);

    var act=document.createElement('div');act.className='actions';
    if(allowStream && canPlay(t.ext)){
      var lbtn=document.createElement('button');lbtn.className='btn-listen';lbtn.textContent='▶';lbtn.setAttribute('aria-label','گوش بده اینجا');
      lbtn.onclick=function(){listen(t);};
      act.appendChild(lbtn);
    }
    var abtn=document.createElement('button');abtn.className='btn-add';abtn.textContent='افزودن';
    abtn.onclick=function(){add(t.id,abtn);};
    act.appendChild(abtn);

    li.appendChild(cov);li.appendChild(m);li.appendChild(act);list.appendChild(li);
  });
}

function add(id,btn){
  btn.disabled=true;var old=btn.textContent;btn.textContent='...';
  fetch('api/add',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({id:id})})
   .then(function(r){return r.json();})
   .then(function(){btn.textContent='✓';showToast('به صف اضافه شد ✓');setTimeout(function(){btn.disabled=false;btn.textContent=old;},1400);})
   .catch(function(){btn.disabled=false;btn.textContent=old;showToast('خطا، دوباره امتحان کن');});
}

/* ---- local playback (player mode) ---- */
function listen(t){
  audio.src='api/stream/'+encodeURIComponent(t.id);
  audio.play().then(function(){
    lbTitle.textContent=t.title||'—';
    fillCover(lbCover,t,44);
    localbar.style.display='flex';lbToggle.textContent='⏸';
  }).catch(function(){showToast('پخش ممکن نشد');});
}
lbToggle.onclick=function(){if(audio.paused){audio.play();lbToggle.textContent='⏸';}else{audio.pause();lbToggle.textContent='▶';}};
lbClose.onclick=function(){audio.pause();audio.removeAttribute('src');audio.load();localbar.style.display='none';};
audio.onended=function(){lbToggle.textContent='▶';};
audio.onpause=function(){lbToggle.textContent='▶';};
audio.onplay=function(){lbToggle.textContent='⏸';};

/* ---- host control (controller mode) ---- */
function control(action){
  fetch('api/control',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:action})})
   .then(function(){setTimeout(pollState,120);}).catch(function(){});
}
hbToggle.onclick=function(){control('toggle');};
hbNext.onclick=function(){control('next');};

/* ---- live host state + interpolated progress ---- */
var stId=null, stPos=0, stDur=0, stPlaying=false, stTs=0;
function pollState(){
  fetch('api/state').then(function(r){return r.json();}).then(function(st){
    if(st.current){
      hostbar.style.display='flex';
      hbTitle.textContent=(st.current.title||'—')+(st.current.artist?(' — '+st.current.artist):'');
      hbToggle.textContent=st.playing?'⏸':'▶';
      if(st.current.id!==stId){stId=st.current.id;fillCover(hbCover,st.current,44);}
      stPos=st.positionMs||0;stDur=st.durationMs||0;stPlaying=!!st.playing;stTs=Date.now();
    }else{ hostbar.style.display='none'; stId=null; }
  }).catch(function(){});
}
function tickProgress(){
  if(hostbar.style.display==='none'||!stDur){return;}
  var pos=stPos+(stPlaying?(Date.now()-stTs):0);
  var pct=Math.max(0,Math.min(100,pos/stDur*100));
  hbBar.style.width=pct+'%';
}

q.oninput=function(){var v=q.value.trim().toLowerCase();
  render(v?all.filter(function(t){return (String(t.title)+' '+String(t.artist)).toLowerCase().indexOf(v)>=0;}):all);};

/* ---- boot ---- */
fetch('api/config').then(function(r){return r.json();}).then(function(c){allowStream=!!c.allowStreaming;})
 .catch(function(){})
 .then(function(){return fetch('api/tracks').then(function(r){return r.json();});})
 .then(function(d){all=d;skeleton.style.display='none';render(all);})
 .catch(function(){skeleton.style.display='none';emptyMsg.textContent='خطا در اتصال به میزبان';empty.style.display='block';});

/* skeleton rows while loading */
(function(){var h='';for(var i=0;i<7;i++){h+='<div class="skrow"><div class="sk cov"></div><div style="flex:1"><div class="sk l1"></div><div class="sk l2"></div></div></div>';}skeleton.innerHTML=h;})();

pollState();
setInterval(pollState,2500);
setInterval(tickProgress,250);
</script>
</body>
</html>
''';
