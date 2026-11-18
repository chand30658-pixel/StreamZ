package com.chand.streamz_tv

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.MediaDrmCallback
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.UUID

class StreamzPlayerViewFactory : PlatformViewFactory(null) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return StreamzPlayerView(context, viewId, params)
    }
}

@OptIn(UnstableApi::class)
class StreamzPlayerView(
    context: Context,
    private val viewId: Int,
    private val params: Map<String, Any?>
) : PlatformView {

    private val root = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val playerView = PlayerView(context)
    private val channel = MethodChannel(
        StreamzPluginMessenger.messenger ?: error("Flutter messenger not initialized"),
        "streamz-exoplayer/$viewId"
    )
    private var player: ExoPlayer? = null

    init {
        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        playerView.useController = false
        playerView.setShutterBackgroundColor(Color.BLACK)
        channel.setMethodCallHandler(::onMethodCall)
        prepare()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setVolume" -> {
                player?.volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                result.success(null)
            }
            "setAspect" -> {
                val mode = call.argument<Int>("mode") ?: 0
                playerView.resizeMode = when (mode) {
                    1 -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    2 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    else -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                }
                result.success(null)
            }
            "play" -> {
                player?.play()
                result.success(null)
            }
            "pause" -> {
                player?.pause()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prepare() {
        val url = params["url"] as? String ?: return
        val headers = mutableMapOf<String, String>()
        @Suppress("UNCHECKED_CAST")
        (params["headers"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (v != null) headers[k] = v.toString()
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)

        var mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)

        val clearKey = params["clearKeyJson"] as? String
        if (!clearKey.isNullOrBlank()) {
            val callback: MediaDrmCallback = LocalMediaDrmCallback(clearKey.toByteArray(Charsets.UTF_8))
            val drmManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .build(callback)
            mediaSourceFactory = mediaSourceFactory.setDrmSessionManagerProvider { drmManager }
        }

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .apply {
                if (!clearKey.isNullOrBlank()) {
                    setDrmConfiguration(
                        MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
                            .setMultiSession(false)
                            .build()
                    )
                }
            }
            .build()

        player = ExoPlayer.Builder(root.context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
            .also { exo ->
                playerView.player = exo
                exo.setMediaItem(mediaItem)
                exo.playWhenReady = true
                exo.prepare()
            }
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        playerView.player = null
        player?.release()
        player = null
        root.removeAllViews()
    }
}

object StreamzPluginMessenger {
    var messenger: BinaryMessenger? = null
}
