import 'dart:convert';
import 'dart:io';

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

    // Live host state so guests see what is playing and what is queued.
    if (path == 'api/state') {
      final cur = player.current;
      return Response.ok(
        jsonEncode({
          'playing': player.playing,
          'current': cur == null ? null : _brief(cur),
          'queue': player.upNext.map(_brief).toList(),
        }),
        headers: _json,
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

/// The self-contained page guests see — RTL, tiffany-themed, no build step.
/// Two modes: add-to-queue / control the host (always), and listen-here
/// (only when the host enabled streaming and the browser can play the format).
const _guestPage = r'''
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>ASplayer - مهمانی</title>
<style>
  :root{--accent:#0ABAB5;--bg:#080808;--card:#111;--line:#161616;--sub:#9aabab;}
  *{box-sizing:border-box;}
  body{margin:0;background:var(--bg);color:#fff;font-family:-apple-system,BlinkMacSystemFont,Tahoma,sans-serif;padding-bottom:150px;}
  header{padding:16px 16px 10px;text-align:center;position:sticky;top:0;background:rgba(8,8,8,.94);z-index:3;backdrop-filter:blur(8px);}
  header h1{margin:0;font-size:20px;font-weight:800;}
  header h1 span{color:var(--accent);}
  header p{margin:5px 0 0;color:var(--sub);font-size:12.5px;}
  #hostbar{display:none;margin:10px auto 0;max-width:520px;align-items:center;gap:10px;padding:8px 12px;background:var(--card);border:1px solid var(--line);border-radius:14px;text-align:right;}
  #hostbar .live{width:8px;height:8px;border-radius:50%;background:var(--accent);flex:none;animation:pulse 1.6s infinite;}
  @keyframes pulse{0%,100%{opacity:.35}50%{opacity:1}}
  #hostbar .hb-meta{min-width:0;flex:1;} #hostbar .hb-meta b{font-weight:600;font-size:13.5px;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  #hostbar .hb-meta small{color:var(--sub);font-size:11px;}
  #hostbar button{flex:none;border:none;background:#1c1c1c;color:#fff;width:38px;height:38px;border-radius:50%;font-size:16px;}
  #hostbar button.main{background:var(--accent);color:#03211f;}
  .search{padding:10px 16px;position:sticky;top:64px;background:var(--bg);z-index:2;}
  .search input{width:100%;padding:12px 18px;border-radius:999px;border:1px solid #2a2a2a;background:var(--card);color:#fff;font-size:15px;outline:none;}
  ul{list-style:none;margin:0;padding:2px 12px 20px;}
  li{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:11px 10px;border-bottom:1px solid var(--line);}
  .meta{min-width:0;flex:1;} .meta b{font-weight:600;font-size:15px;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  .meta small{color:var(--sub);font-size:12px;}
  .actions{flex:none;display:flex;gap:6px;}
  button.add{border:none;background:var(--accent);color:#03211f;font-weight:700;padding:9px 15px;border-radius:999px;font-size:13px;}
  button.listen{border:1px solid var(--accent);background:transparent;color:var(--accent);font-weight:700;width:40px;border-radius:999px;font-size:15px;}
  button:disabled{opacity:.55;}
  #localbar{display:none;position:fixed;bottom:16px;left:50%;transform:translateX(-50%);width:calc(100% - 24px);max-width:520px;align-items:center;gap:10px;padding:10px 12px;background:#0d1a19;border:1px solid var(--accent);border-radius:16px;z-index:4;text-align:right;}
  #localbar .lb-meta{min-width:0;flex:1;} #localbar .lb-meta b{font-weight:600;font-size:14px;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  #localbar .lb-meta small{color:var(--accent);font-size:11px;}
  #localbar button{flex:none;border:none;background:var(--accent);color:#03211f;width:40px;height:40px;border-radius:50%;font-size:17px;}
  #localbar button.close{background:#1c1c1c;color:#fff;width:34px;height:34px;font-size:15px;}
  #toast{position:fixed;bottom:92px;left:50%;transform:translateX(-50%);background:var(--accent);color:#03211f;padding:11px 20px;border-radius:999px;font-weight:700;opacity:0;transition:opacity .3s;z-index:5;pointer-events:none;}
  #toast.show{opacity:1;}
  #empty{color:var(--sub);text-align:center;padding:40px 20px;}
</style>
</head>
<body>
<header>
  <h1><span>AS</span>player · مهمانی</h1>
  <p>آهنگ به صف اضافه کن، پخشِ میزبان رو کنترل کن</p>
  <div id="hostbar">
    <span class="live"></span>
    <div class="hb-meta"><b id="hbTitle">—</b><small>پخش روی میزبان</small></div>
    <button id="hbToggle">⏯</button>
    <button id="hbNext" class="main">⏭</button>
  </div>
</header>
<div class="search"><input id="q" placeholder="جست‌وجوی آهنگ..."></div>
<ul id="list"></ul>
<div id="empty" style="display:none">آهنگی نیست</div>

<div id="localbar">
  <button id="lbToggle">⏸</button>
  <div class="lb-meta"><b id="lbTitle">—</b><small>پخش روی این دستگاه</small></div>
  <button id="lbClose" class="close">✕</button>
</div>
<audio id="audio" preload="none"></audio>
<div id="toast"></div>

<script>
var all=[], allowStream=false;
var list=document.getElementById('list'), q=document.getElementById('q'),
    toast=document.getElementById('toast'), empty=document.getElementById('empty'),
    audio=document.getElementById('audio'),
    localbar=document.getElementById('localbar'), lbTitle=document.getElementById('lbTitle'),
    lbToggle=document.getElementById('lbToggle'), lbClose=document.getElementById('lbClose'),
    hostbar=document.getElementById('hostbar'), hbTitle=document.getElementById('hbTitle'),
    hbToggle=document.getElementById('hbToggle'), hbNext=document.getElementById('hbNext');

function mimeFor(ext){
  return {mp3:'audio/mpeg',m4a:'audio/mp4',aac:'audio/aac',wav:'audio/wav',
          flac:'audio/flac',ogg:'audio/ogg',opus:'audio/ogg'}[ext]||'';
}
function canPlay(ext){
  var m=mimeFor(ext); if(!m) return false;
  try{ return audio.canPlayType(m)!==''; }catch(e){ return false; }
}
function showToast(m){toast.textContent=m;toast.classList.add('show');setTimeout(function(){toast.classList.remove('show');},1500);}

function render(items){
  list.innerHTML='';
  empty.style.display=items.length?'none':'block';
  items.slice(0,400).forEach(function(t){
    var li=document.createElement('li');
    var m=document.createElement('div');m.className='meta';
    var b=document.createElement('b');b.textContent=t.title||'—';
    var s=document.createElement('small');s.textContent=t.artist||'';
    m.appendChild(b);m.appendChild(s);

    var act=document.createElement('div');act.className='actions';
    if(allowStream && canPlay(t.ext)){
      var lbtn=document.createElement('button');lbtn.className='listen';lbtn.textContent='▶';
      lbtn.title='گوش بده اینجا';
      lbtn.onclick=function(){listen(t);};
      act.appendChild(lbtn);
    }
    var abtn=document.createElement('button');abtn.className='add';abtn.textContent='افزودن';
    abtn.onclick=function(){add(t.id,abtn);};
    act.appendChild(abtn);

    li.appendChild(m);li.appendChild(act);list.appendChild(li);
  });
}

function add(id,btn){
  btn.disabled=true;btn.textContent='...';
  fetch('api/add',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({id:id})})
   .then(function(r){return r.json();})
   .then(function(){btn.textContent='✓';showToast('اضافه شد ✓');setTimeout(function(){btn.disabled=false;btn.textContent='افزودن';},1400);})
   .catch(function(){btn.disabled=false;btn.textContent='افزودن';showToast('خطا، دوباره امتحان کن');});
}

function listen(t){
  audio.src='api/stream/'+encodeURIComponent(t.id);
  audio.play().then(function(){
    lbTitle.textContent=t.title||'—';
    lbToggle.textContent='⏸';
    localbar.style.display='flex';
  }).catch(function(){showToast('پخش ممکن نشد');});
}
lbToggle.onclick=function(){
  if(audio.paused){audio.play();lbToggle.textContent='⏸';}
  else{audio.pause();lbToggle.textContent='▶';}
};
lbClose.onclick=function(){audio.pause();audio.removeAttribute('src');audio.load();localbar.style.display='none';};
audio.onended=function(){lbToggle.textContent='▶';};

function control(action){
  fetch('api/control',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:action})})
   .then(function(){setTimeout(pollState,150);}).catch(function(){});
}
hbToggle.onclick=function(){control('toggle');};
hbNext.onclick=function(){control('next');};

function pollState(){
  fetch('api/state').then(function(r){return r.json();}).then(function(st){
    if(st.current){
      hostbar.style.display='flex';
      hbTitle.textContent=(st.current.title||'—')+(st.current.artist?(' — '+st.current.artist):'');
      hbToggle.textContent=st.playing?'⏸':'▶';
    }else{ hostbar.style.display='none'; }
  }).catch(function(){});
}

q.oninput=function(){var v=q.value.trim().toLowerCase();
  render(v?all.filter(function(t){return (String(t.title)+' '+String(t.artist)).toLowerCase().indexOf(v)>=0;}):all);};

fetch('api/config').then(function(r){return r.json();}).then(function(c){allowStream=!!c.allowStreaming;})
 .catch(function(){})
 .then(function(){
   return fetch('api/tracks').then(function(r){return r.json();}).then(function(d){all=d;render(all);});
 })
 .catch(function(){empty.textContent='خطا در اتصال';empty.style.display='block';});

pollState();
setInterval(pollState,2500);
</script>
</body>
</html>
''';
