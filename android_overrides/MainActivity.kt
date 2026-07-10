package ir.aspoormehr.asplayer

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service needs the activity to extend AudioServiceActivity rather than
// the default FlutterActivity, otherwise the media notification loses the app.
class MainActivity : AudioServiceActivity()
