import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../data/library_store.dart';
import '../models.dart';

/// A tiny web server the host runs during a party. Guests scan a QR, open the
/// served page in any browser (no app needed), search the host's library and
/// add songs to the host's queue. Audio files never leave the host — only the
/// title/artist and a track id cross the wire, and only "add to queue" is
/// allowed (no download), so it stays clean.
class PartyServer {
  PartyServer({required this.store, required this.onAdd});

  final LibraryStore store;
  final void Function(Track track) onAdd;

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

  Future<Response> _handle(Request req) async {
    final path = req.url.path;

    if (path.isEmpty || path == 'index.html') {
      return Response.ok(_guestPage, headers: {'content-type': 'text/html; charset=utf-8'});
    }

    if (path == 'api/tracks') {
      final data = store.tracks
          .map((t) => {'id': t.id, 'title': t.title, 'artist': t.artist})
          .toList();
      return Response.ok(jsonEncode(data), headers: _json);
    }

    if (path == 'api/add' && req.method == 'POST') {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final track = store.byId(body['id'] as String);
        if (track != null) {
          onAdd(track);
          addedCount++;
          return Response.ok(jsonEncode({'ok': true, 'title': track.title}), headers: _json);
        }
      } catch (_) {
        // fall through to 404
      }
      return Response.notFound(jsonEncode({'ok': false}), );
    }

    return Response.notFound('not found');
  }

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
const _guestPage = r'''
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>ASplayer - مهمانی</title>
<style>
  :root{--accent:#0ABAB5;--bg:#080808;--sub:#9aabab;}
  *{box-sizing:border-box;}
  body{margin:0;background:var(--bg);color:#fff;font-family:-apple-system,BlinkMacSystemFont,Tahoma,sans-serif;}
  header{padding:18px 16px;text-align:center;position:sticky;top:0;background:rgba(8,8,8,.92);z-index:2;}
  header h1{margin:0;font-size:20px;font-weight:800;}
  header h1 span{color:var(--accent);}
  header p{margin:6px 0 0;color:var(--sub);font-size:13px;}
  .search{padding:8px 16px 12px;position:sticky;top:66px;background:var(--bg);z-index:2;}
  .search input{width:100%;padding:12px 18px;border-radius:999px;border:1px solid #2a2a2a;background:#111;color:#fff;font-size:15px;outline:none;}
  ul{list-style:none;margin:0;padding:4px 12px 48px;}
  li{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 10px;border-bottom:1px solid #161616;}
  .meta{min-width:0;} .meta b{font-weight:600;font-size:15px;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  .meta small{color:var(--sub);font-size:12px;}
  button.add{flex:none;border:none;background:var(--accent);color:#03211f;font-weight:700;padding:9px 15px;border-radius:999px;font-size:13px;}
  button.add:disabled{opacity:.6;}
  #toast{position:fixed;bottom:22px;left:50%;transform:translateX(-50%);background:var(--accent);color:#03211f;padding:11px 20px;border-radius:999px;font-weight:700;opacity:0;transition:opacity .3s;z-index:3;}
  #toast.show{opacity:1;}
  #empty{color:var(--sub);text-align:center;padding:40px 20px;}
</style>
</head>
<body>
<header><h1><span>AS</span>player · مهمانی</h1><p>آهنگ دلخواهت رو به صف اضافه کن</p></header>
<div class="search"><input id="q" placeholder="جست‌وجوی آهنگ..."></div>
<ul id="list"></ul>
<div id="empty" style="display:none">آهنگی نیست</div>
<div id="toast"></div>
<script>
var all=[];
var list=document.getElementById('list'),q=document.getElementById('q'),toast=document.getElementById('toast'),empty=document.getElementById('empty');
function render(items){
  list.innerHTML='';
  empty.style.display=items.length?'none':'block';
  items.slice(0,300).forEach(function(t){
    var li=document.createElement('li');
    var m=document.createElement('div');m.className='meta';
    var b=document.createElement('b');b.textContent=t.title||'—';
    var s=document.createElement('small');s.textContent=t.artist||'';
    m.appendChild(b);m.appendChild(s);
    var btn=document.createElement('button');btn.className='add';btn.textContent='افزودن';
    btn.onclick=function(){add(t.id,btn);};
    li.appendChild(m);li.appendChild(btn);list.appendChild(li);
  });
}
function add(id,btn){
  btn.disabled=true;btn.textContent='...';
  fetch('api/add',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({id:id})})
   .then(function(r){return r.json();})
   .then(function(){btn.textContent='✓';showToast('اضافه شد ✓');setTimeout(function(){btn.disabled=false;btn.textContent='افزودن';},1500);})
   .catch(function(){btn.disabled=false;btn.textContent='افزودن';showToast('خطا، دوباره امتحان کن');});
}
function showToast(m){toast.textContent=m;toast.classList.add('show');setTimeout(function(){toast.classList.remove('show');},1500);}
q.oninput=function(){var v=q.value.trim().toLowerCase();render(v?all.filter(function(t){return (String(t.title)+' '+String(t.artist)).toLowerCase().indexOf(v)>=0;}):all);};
fetch('api/tracks').then(function(r){return r.json();}).then(function(d){all=d;render(all);}).catch(function(){empty.textContent='خطا در اتصال';empty.style.display='block';});
</script>
</body>
</html>
''';
