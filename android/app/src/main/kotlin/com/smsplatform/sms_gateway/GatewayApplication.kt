package com.smsplatform.sms_gateway

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import com.pravera.flutter_foreground_task.service.ForegroundService

/**
 * flutter_foreground_task's background isolate runs on its own bare
 * FlutterEngine that it constructs itself (`FlutterEngine(context)`) —
 * critically, WITHOUT calling GeneratedPluginRegistrant, unlike the engine
 * FlutterActivity sets up for the normal UI isolate. Without this listener,
 * every plugin (sqflite, flutter_secure_storage, permission_handler, and
 * this app's own sms_channel) would throw MissingPluginException the
 * instant the background heartbeat/lease/send/report loop touched them.
 *
 * `ForegroundTaskLifecycleListener.onEngineCreate` is exactly the hook the
 * package provides for this ("Initialize the service you want to use in
 * the task. (like PlatformChannel initialization)") — registered here in
 * Application.onCreate() so it's wired up even for a headless restart after
 * reboot, where MainActivity never runs at all.
 */
class GatewayApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        ForegroundService.addTaskLifecycleListener(object : FlutterForegroundTaskLifecycleListener {
            override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                if (flutterEngine != null) {
                    GeneratedPluginRegistrant.registerWith(flutterEngine)
                }
            }

            override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}
            override fun onTaskRepeatEvent() {}
            override fun onTaskDestroy() {}
            override fun onEngineWillDestroy() {}
        })
    }
}
