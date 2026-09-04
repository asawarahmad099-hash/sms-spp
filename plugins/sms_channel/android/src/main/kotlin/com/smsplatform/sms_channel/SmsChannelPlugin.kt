package com.smsplatform.sms_channel

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Native SMS sending + SIM enumeration, packaged as a real Flutter plugin
 * (not MainActivity-only code) specifically so it auto-registers on every
 * FlutterEngine the host app creates — including flutter_foreground_task's
 * background isolate, which builds its own bare-ish engine and does NOT
 * see anything registered only in MainActivity.configureFlutterEngine().
 *
 * Deliberately hand-written rather than a third-party package: the obvious
 * one (`telephony`) is archived/unmaintained, and this is the single most
 * safety-critical operation in the whole app. SmsManager/SubscriptionManager
 * are stable public Android APIs (since API 22).
 */
class SmsChannelPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.smsplatform.sms_gateway/sms")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "listSims" -> result.success(listSims())
            "sendSms" -> {
                val subscriptionId = call.argument<Int>("subscriptionId")
                val recipient = call.argument<String>("recipient")
                val body = call.argument<String>("body")

                if (subscriptionId == null || recipient == null || body == null) {
                    result.error("INVALID_ARGS", "subscriptionId, recipient, and body are required", null)
                    return
                }

                try {
                    sendSms(subscriptionId, recipient, body)
                    result.success(null)
                } catch (e: SecurityException) {
                    result.error("PERMISSION_DENIED", e.message, null)
                } catch (e: Exception) {
                    result.error("SEND_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * Returns a list of maps: slotIndex, subscriptionId, carrierName,
     * phoneNumber. Requires READ_PHONE_STATE; the phone number specifically
     * also needs READ_PHONE_NUMBERS — other fields are still returned
     * without it.
     */
    private fun listSims(): List<Map<String, Any?>> {
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            return emptyList()
        }

        val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as? SubscriptionManager ?: return emptyList()

        val infoList = try {
            subscriptionManager.activeSubscriptionInfoList
        } catch (e: SecurityException) {
            null
        } ?: return emptyList()

        val canReadNumber = hasPermission(Manifest.permission.READ_PHONE_NUMBERS)

        return infoList.map { info ->
            mapOf(
                "slotIndex" to info.simSlotIndex,
                "subscriptionId" to info.subscriptionId,
                "carrierName" to info.carrierName?.toString(),
                // SubscriptionInfo.number is deprecated (API 33+ prefers
                // SubscriptionManager.getPhoneNumber(subId)) but remains
                // functional across this app's minSdk 23 target — using the
                // single deprecated call avoids branching on API level for
                // what's only a diagnostic display field, not something the
                // send path depends on.
                "phoneNumber" to if (canReadNumber) {
                    try {
                        @Suppress("DEPRECATION")
                        info.number?.ifBlank { null }
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    null
                },
            )
        }
    }

    /**
     * Sends via the SIM identified by [subscriptionId] (not slot index —
     * the Dart side resolves slotIndex -> subscriptionId itself, since only
     * subscriptionId is what SmsManager accepts). Splits into multipart if
     * [body] exceeds one SMS segment, since campaign bodies can be up to
     * 1600 characters (the backend's own validation limit).
     */
    private fun sendSms(subscriptionId: Int, recipient: String, body: String) {
        if (!hasPermission(Manifest.permission.SEND_SMS)) {
            throw SecurityException("SEND_SMS permission not granted")
        }

        val smsManager = SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        val parts = smsManager.divideMessage(body)

        if (parts.size <= 1) {
            smsManager.sendTextMessage(recipient, null, body, null, null)
        } else {
            smsManager.sendMultipartTextMessage(recipient, null, parts, null, null)
        }
    }
}
