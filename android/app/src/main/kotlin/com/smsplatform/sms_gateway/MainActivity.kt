package com.smsplatform.sms_gateway

import io.flutter.embedding.android.FlutterActivity

// SMS/SIM native code lives in the local `sms_channel` plugin (../../../../../../plugins/sms_channel),
// not here — a channel registered only in MainActivity is invisible to
// flutter_foreground_task's background isolate, which builds its own
// FlutterEngine. A real plugin auto-registers on every engine instead.
class MainActivity : FlutterActivity()
