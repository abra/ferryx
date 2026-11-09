package io.github.abra.native_text_selection

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeTextSelectionPlugin : FlutterPlugin {
    private var capabilities: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            NativeSelectionFactory(messenger),
        )
        capabilities =
            MethodChannel(messenger, "io.github.abra.native_text_selection/capabilities").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "isAvailable") result.success(true) else result.notImplemented()
                }
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        capabilities?.setMethodCallHandler(null)
        capabilities = null
    }

    companion object {
        const val VIEW_TYPE = "io.github.abra.native_text_selection/surface"
    }
}

private class NativeSelectionFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?,
    ): PlatformView = NativeSelectionSurface(context, viewId, messenger, args as? Map<*, *>)
}
