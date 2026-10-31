package com.intunix.reactnative

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.intunix.sdk.Intunix
import com.intunix.sdk.IntunixOptions

/** Bridges `NativeModules.Intunix` to the native Intunix Android SDK. */
class IntunixModule(private val ctx: ReactApplicationContext) : ReactContextBaseJavaModule(ctx) {
    override fun getName() = "Intunix"

    @ReactMethod
    fun initialize(apiKey: String, options: ReadableMap) {
        val o = options.toHashMap()
        Intunix.init(
            currentActivity ?: ctx.applicationContext, apiKey,
            IntunixOptions(
                apiHost = o["apiHost"] as? String ?: "https://api.intunix.com",
                register = (o["register"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                registerAll = o["registerAll"] as? Boolean ?: false,
                flushIntervalMs = (o["flushIntervalMs"] as? Number)?.toLong() ?: 5_000,
                maxQueueSize = (o["maxQueueSize"] as? Number)?.toInt() ?: 100,
                screenTriggerDelayMs = (o["screenTriggerDelayMs"] as? Number)?.toLong() ?: 600,
                disableEventApi = o["disableEventApi"] as? Boolean ?: false,
                debug = o["debug"] as? Boolean ?: false,
            ),
        )
        currentActivity?.let { Intunix.attach(it) }
    }

    @ReactMethod fun identify(userId: String, traits: ReadableMap) = Intunix.identify(userId, traits.toHashMap())
    @ReactMethod fun reset() = Intunix.reset()
    @ReactMethod fun track(event: String, properties: ReadableMap) = Intunix.track(event, properties.toHashMap())
    @ReactMethod fun screen(name: String) = Intunix.screen(name)
    @ReactMethod fun setContext(context: ReadableMap?) = Intunix.setContext(context?.toHashMap())
    @ReactMethod fun showForm(form: String, context: ReadableMap?) { Intunix.showForm(form, context?.toHashMap()) }
    @ReactMethod fun register(form: String) { Intunix.register(form) }
    @ReactMethod fun unregister(form: String) { Intunix.unregister(form) }
}
