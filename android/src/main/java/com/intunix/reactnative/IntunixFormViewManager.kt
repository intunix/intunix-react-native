package com.intunix.reactnative

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.intunix.sdk.IntunixFormView

/** `IntunixFormView` native component: the inline form, reporting height and completion. */
class IntunixFormViewManager : SimpleViewManager<IntunixFormView>() {
    override fun getName() = "IntunixFormView"

    override fun createViewInstance(context: ThemedReactContext): IntunixFormView = IntunixFormView(context).apply {
        onHeightChanged = { px -> emit(this, "topHeightChange") { putDouble("height", PixelUtil.toDIPFromPixel(px.toFloat()).toDouble()) } }
        onFinished = { emit(this, "topFinished") {} }
    }

    @ReactProp(name = "form")
    fun setForm(view: IntunixFormView, form: String?) {
        view.setTag(R_FORM, form)
        @Suppress("UNCHECKED_CAST")
        view.setForm(form, view.getTag(R_CONTEXT) as? Map<String, Any?>)
    }

    @ReactProp(name = "formContext")
    fun setFormContext(view: IntunixFormView, context: ReadableMap?) {
        val map = context?.toHashMap()
        view.setTag(R_CONTEXT, map)
        (view.getTag(R_FORM) as? String)?.let { view.setForm(it, map) }
    }

    override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> = mapOf(
        "topHeightChange" to mapOf("registrationName" to "onHeightChange"),
        "topFinished" to mapOf("registrationName" to "onFinished"),
    )

    private fun emit(view: IntunixFormView, name: String, fill: com.facebook.react.bridge.WritableMap.() -> Unit) {
        val payload = Arguments.createMap().apply(fill)
        (view.context as ReactContext).getJSModule(RCTEventEmitter::class.java).receiveEvent(view.id, name, payload)
    }

    // Keyed tags: React Native uses the plain tag for testID.
    private companion object {
        val R_FORM = R.id.intunix_form_id
        val R_CONTEXT = R.id.intunix_form_context
    }
}
