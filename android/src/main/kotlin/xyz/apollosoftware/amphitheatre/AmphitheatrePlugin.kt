package xyz.apollosoftware.amphitheatre

import android.app.Activity
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.StatFs
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.Transformer.ProgressState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.min

const val TAG = "amphitheatre"

const val kChannelName = "xyz.apollosoftware.amphitheatre"
const val eventChannelId = "events"

/**
 * An error that can be delivered to Flutter.
 *
 * @param code The error code. This can be parsed to provide localized error strings, if necessary.
 * @param message The human-readable message.
 * @param details The error details, optionally provided.
 */
class FlutterError(val code: String, override val message: String, val details: Any? = null): Exception()

/**
 * An in-progress export session.
 *
 * The session owns the outcome of its export: [result] is settled exactly once, by whichever of
 * [complete], [fail] or [cancel] happens first, and the other two then do nothing. Every one of
 * those paths runs on the transformer's application looper (the main thread), which is where the
 * Transformer must be driven and where the event sink must be used.
 *
 * @param activity The activity that started the export session.
 * @param id The ID of the session.
 * @param args The arguments that the export session was started with.
 * @param transformer The transformer performing the export.
 * @param path The path the output is written to.
 */
@OptIn(UnstableApi::class)
internal class AmphitheatreExportSession(val activity: Activity, val id: String, val args: AmphitheatrePlugin.CropVideoArgs, val transformer: Transformer, val path: String) {

  /**
   * The outcome of the export: the output path on success, or the [FlutterError] it ended with.
   */
  val result = CompletableDeferred<String>()

  /** Posts to the transformer's application looper. */
  val handler = Handler(transformer.applicationLooper)

  /**
   * The event sink for the export session - where progress updates should be delivered.
   *
   * This is bound with [bind] on-demand when the Flutter code wishes to receive status updates (by
   * subscribing to the stream).
   */
  var sink: EventChannel.EventSink? = null

  /** Whether the export is still running, i.e., no terminal path has settled [result] yet. */
  val isActive: Boolean get() = !result.isCompleted

  /**
   * Bind the given [EventChannel.EventSink] to the export session.
   *
   * Once the event sink is bound, progress updates will be delivered to the event sink as they
   * become available.
   */
  fun bind(sink: EventChannel.EventSink?) {
    if (this.sink != null) {
      throw FlutterError(code = "CONFLICTING_BIND", message = "tried to bind an event sink to a session that was already bound ($id)")
    }

    this.sink = sink

    // A subscription that arrives after the export concluded still gets the terminal state.
    if (!isActive) {
      if (result.getCompletionExceptionOrNull() == null) notifyProgress(1.0)
      close()
    }
  }

  /**
   * Deliver the status update to Flutter.
   *
   * @param status The new status to deliver.
   */
  fun notify(status: Any) {
    this.sink?.success(status)
  }

  /** Deliver a progress update (0.0 to 1.0) for the export to Flutter. */
  fun notifyProgress(progress: Double) {
    notify(mapOf(
      "sessionId" to id,
      "stage" to "export",
      "quality" to args.quality.rawValue,
      "progress" to progress,
    ))
  }

  /**
   * End the event stream bound to the export session (if any).
   */
  fun close() {
    this.sink?.endOfStream()
  }

  /**
   * Settle the session successfully: the output at [path] is complete.
   *
   * Reports 100% and ends the event stream. Does nothing if the session was already settled.
   */
  fun complete() {
    if (!result.complete(path)) return

    notifyProgress(1.0)
    close()
  }

  /**
   * Settle the session with [error], deleting the partial output.
   *
   * Does nothing if the session was already settled.
   */
  fun fail(error: FlutterError) {
    if (!result.completeExceptionally(error)) return

    File(path).delete()
    close()
  }

  /**
   * Cancel the export session.
   *
   * Stops the transformer, deletes the partial output and settles [result] with
   * `EXPORT_CANCELLED`. Safe to call from any thread, and after the export has concluded (in which
   * case nothing happens: a completed output is never deleted).
   */
  fun cancel() {
    handler.post {
      val cancelled = result.completeExceptionally(FlutterError(
        code = "EXPORT_CANCELLED",
        message = "the export session was cancelled",
      ))
      if (!cancelled) return@post

      // Transformer.cancel() fires neither listener callback, so the session has to settle itself.
      transformer.cancel()
      File(path).delete()
      close()
    }
  }

}

/** AmphitheatrePlugin */
class AmphitheatrePlugin: FlutterPlugin, EventChannel.StreamHandler, MethodCallHandler, ActivityAware {
  /** The MethodChannel that will handle communication between Flutter and Android. */
  private lateinit var channel: MethodChannel

  /** The EventChannel that will handle bidirectional communication between Flutter and Android. */
  private lateinit var eventChannel: EventChannel

  /** The Activity that the application is currently bound to. */
  private var activity: Activity? = null

  /**
   * The export sessions, keyed by session ID.
   *
   * A session stays here until it is awaited (see [awaitCropVideo]) or cancelled, so an export that
   * concludes before Flutter gets to await it still delivers its outcome rather than
   * `UNKNOWN_SESSION`.
   */
  private var sessions: ConcurrentHashMap<String, AmphitheatreExportSession> = ConcurrentHashMap()

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    if (arguments == null) return

    val args = SessionArgs.parse(arguments as Map<*, *>)
    val session = sessions[args.sessionId]

    // The session is discarded once awaited (see awaitCropVideo), so a subscription that arrives
    // after a fast export concluded has nothing left to report: the stream simply ends.
    if (session == null) {
      Log.w(TAG, "status subscription for an unknown or concluded session: ${args.sessionId}")
      sink?.endOfStream()
      return
    }

    session.bind(sink)
  }

  override fun onCancel(arguments: Any?) {
    if (arguments == null) return

    val args = SessionArgs.parse(arguments as Map<*, *>)
    sessions.remove(args.sessionId)?.cancel()
  }

  /**
   * Clean up any sessions that are not bound to the current activity.
   */
  fun cleanUp() {
    sessions.forEach { (sessionId, session) ->
      if (session.activity == activity) {
        Log.d(TAG, "Cleaning up session: $sessionId")
        session.cancel()
        sessions.remove(sessionId)
      }
    }
  }

  fun getTemporaryDirectory(): String {
    // Create the cache directory if it does not already exist.
    val cacheDir = File(activity!!.cacheDir.absolutePath, kChannelName)
    if (!cacheDir.exists()) cacheDir.mkdirs()
    return cacheDir.absolutePath
  }

  internal fun deleteFile(args: DeleteFileArgs) {
    File(args.path).delete()
  }

  fun getAvailableDiskSpace(): Long {
    try {
      return StatFs(activity!!.cacheDir.absolutePath).availableBytes
    } catch (_: Throwable) {
      throw FlutterError(code = "GET_AVAILABLE_DISK_SPACE_FAILED", message = "failed to determine number of available bytes on disk")
    }
  }

  @OptIn(ExperimentalApi::class, UnstableApi::class)
  internal fun checkCropVideoDiskSpace(args: CropVideoArgs) {
    val (path, start, end, quality) = args

    // A passthrough export copies from the sync sample at or before the requested start (see
    // startCropVideo), so that is the range whose size matters.
    val effectiveStartMs = if (quality == CropVideoQuality.Passthrough) {
      (previousSyncSampleUs(path, start) ?: start * 1000) / 1000
    } else {
      start
    }
    val cropDurationMs = end - effectiveStartMs
    var durationMs: Long? = null
    val retriever = MediaMetadataRetriever()

    try {
      retriever.setDataSource(path)
      durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong()
    } catch (_: Exception) {
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {}
    }

    if (durationMs == null || durationMs <= 0) {
      return
    }

    // Scale the file size by the proportion of the video that is kept, to produce an estimate of
    // the expected output file size.
    val fileSizeBytes = File(path).length()
    val cropMs = min(cropDurationMs, durationMs)

    val requiredBytes = fileSizeBytes.toDouble() * (cropMs.toDouble() / durationMs.toDouble())
    val availableBytes = getAvailableDiskSpace()

    if (requiredBytes > availableBytes) {
      throw FlutterError(
        code = "EXCEEDS_DISK_SPACE",
        message = "There is not enough free space on this device to process the video.",
        details = mapOf(
          "requiredBytes" to requiredBytes,
          "availableBytes" to availableBytes,
        )
      )
    }
  }

  /**
   * Start exporting the crop described by [args] and return the ID of the new session.
   *
   * `passthrough` is a stream copy: the start is moved back to the video sync sample at or before
   * the requested start and declared a key frame, so media3 transmuxes instead of re-encoding the
   * whole clip (its trim optimization, which would re-encode only the first GOP, stays off: with it
   * on, media3 reports progress as permanently unavailable). The output therefore starts up to one
   * GOP before the handle. When the sample cannot be resolved the requested start is kept and not
   * declared a key frame, and media3 transcodes as before rather than act on a false assertion. The
   * named qualities transcode to H.264/AAC: `presetHD` and `presetFullHD` scale down to 720 or
   * 1080 lines (never up), `highest` keeps the source size.
   *
   * The output is `<sessionId>.mp4` in the plugin's temporary directory, as on iOS.
   */
  @OptIn(ExperimentalApi::class, UnstableApi::class)
  internal fun startCropVideo(args: CropVideoArgs): String {
    val (path, start, end, quality) = args

    // Acquire a new session ID.
    var sessionId: String
    do {
      sessionId = UUID.randomUUID().toString()
    } while (sessions.containsKey(sessionId))

    val inputFile = File(path)

    // Make sure the input file exists. Returning the same error if the input file is a
    // directory (instead of a file, as expected) mirrors the semantics of the iOS
    // implementation.
    if (!inputFile.exists() || inputFile.isDirectory) {
      throw FlutterError(
        code = "ERR_SEARCH_FAIL",
        message = "Failed to locate the provided file."
      )
    }

    val outputFile = File(getTemporaryDirectory(), "$sessionId.mp4")
    outputFile.delete()
    val outputPath = outputFile.absolutePath

    val syncStartUs = if (quality == CropVideoQuality.Passthrough) previousSyncSampleUs(path, start) else null
    val clippingConfiguration = MediaItem.ClippingConfiguration.Builder().apply {
      if (syncStartUs != null) {
        setStartPositionUs(syncStartUs)
        setStartsAtKeyFrame(true)
      } else {
        setStartPositionMs(start)
      }
      setEndPositionMs(end)
    }.build()

    val mediaItem = MediaItem.Builder()
      .setUri(path)
      .setClippingConfiguration(clippingConfiguration)
      .build()

    val targetHeight: Int? = when (quality) {
      CropVideoQuality.PresetHD -> 720
      CropVideoQuality.PresetFullHD -> 1080
      else -> null
    }

    val editedMediaItem = EditedMediaItem.Builder(mediaItem).apply {
      // Only scale down. When the height is unknown (or the file has no video track) no effect is
      // added: a video effect on an audio-only file fails the export.
      if (targetHeight != null) {
        val sourceHeight = displayHeightOf(path)
        if (sourceHeight > targetHeight) {
          setEffects(Effects(emptyList(), listOf(Presentation.createForHeight(targetHeight))))
        }
      }
    }.build()

    val transformer = Transformer.Builder(activity!!.baseContext)
      .experimentalSetTrimOptimizationEnabled(false)
      .apply {
        if (quality != CropVideoQuality.Passthrough) {
          setVideoMimeType(MimeTypes.VIDEO_H264)
          setAudioMimeType(MimeTypes.AUDIO_AAC)
        }
      }
      .build()

    val session = AmphitheatreExportSession(activity!!, sessionId, args, transformer, outputPath)
    sessions[sessionId] = session

    val progressHolder = ProgressHolder()
    val mainHandler = session.handler

    mainHandler.post {
      // The listener is attached before the export starts, so no outcome can be missed.
      transformer.addListener(object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
          session.complete()
        }

        override fun onError(
          composition: Composition,
          exportResult: ExportResult,
          exportException: ExportException
        ) {
          session.fail(FlutterError(
            code = "EXPORT_FAILED",
            message = exportException.message ?: "an error occurred during the export session",
            details = mapOf(
              "errorCode" to exportException.errorCode,
              "errorCodeName" to ExportException.getErrorCodeName(exportException.errorCode),
            ),
          ))
        }
      })

      try {
        transformer.start(editedMediaItem, outputPath)
      } catch (error: Exception) {
        session.fail(FlutterError(
          code = "EXPORT_FAILED",
          message = error.message ?: "the export session could not be started",
        ))
        return@post
      }

      var started = false
      mainHandler.post(
        object : Runnable {
          override fun run() {
            // The poll ends with the session.
            if (!session.isActive) return

            val state: @ProgressState Int = transformer.getProgress(progressHolder)
            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
              session.notifyProgress(progressHolder.progress.toDouble() / 100.0)
            }

            if (state != Transformer.PROGRESS_STATE_NOT_STARTED) {
              started = true
            }

            // If not resumed or completed, keep polling for the state.
            // See https://developer.android.com/media/media3/transformer/getting-started#progress
            if (state != Transformer.PROGRESS_STATE_UNAVAILABLE &&
                (state != Transformer.PROGRESS_STATE_NOT_STARTED || !started)) {
              mainHandler.postDelayed(this, 15)
            }
          }
        }
      )
    }

    return sessionId
  }

  /**
   * The presentation time, in microseconds, of the video sync sample at or before [startMs] in the
   * file at [path]. A file without a video track has nothing to snap and answers [startMs] itself.
   * Null when the sample cannot be determined (unreadable file, extractor failure).
   */
  private fun previousSyncSampleUs(path: String, startMs: Long): Long? {
    val extractor = MediaExtractor()
    return try {
      extractor.setDataSource(path)
      val video = (0 until extractor.trackCount).firstOrNull { track ->
        extractor.getTrackFormat(track).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
      } ?: return startMs * 1000
      extractor.selectTrack(video)
      extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
      val sampleUs = extractor.sampleTime
      if (sampleUs < 0 || sampleUs > startMs * 1000) null else sampleUs
    } catch (_: Exception) {
      null
    } finally {
      extractor.release()
    }
  }

  /**
   * The height of the video at [path] in display orientation, or -1 if it cannot be determined
   * (e.g., the file has no video track).
   */
  private fun displayHeightOf(path: String): Int {
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(path)
      val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
      val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
      val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0

      if (width == null || height == null) -1
      else if (rotation == 90 || rotation == 270) width
      else height
    } catch (_: Exception) {
      -1
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {}
    }
  }

  /**
   * Look up the session for [args], for [awaitCropVideo].
   *
   * Called on the platform thread, where the method call arrives, so that the lookup happens in
   * message order: the EventChannel cancel that Flutter sends once the status stream ends (which
   * removes the session) is always a later message.
   */
  internal fun lookUpCropVideo(args: SessionArgs): AmphitheatreExportSession =
    sessions[args.sessionId] ?: throw FlutterError(
      code = "UNKNOWN_SESSION",
      message = "invalid session ID",
      details = args.sessionId
    )

  /**
   * Await the outcome of the [session]: the output path, or the [FlutterError] the export ended
   * with (`EXPORT_FAILED`, or `EXPORT_CANCELLED` when the session was cancelled). The session is
   * discarded once awaited.
   */
  internal suspend fun awaitCropVideo(session: AmphitheatreExportSession): String {
    try {
      return session.result.await()
    } finally {
      sessions.remove(session.id, session)
    }
  }

  internal fun emptyResponse(unit: Unit): Any? {
    return null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (activity == null) {
      return result.error("ERR_BAD_ACCESS", "There is no activity to bind the action to.", null)
    }

    // Resolved before the coroutine is dispatched: see lookUpCropVideo.
    val awaitedSession: AmphitheatreExportSession? = if (call.method == "awaitCropVideo") {
      try {
        lookUpCropVideo(SessionArgs.parse(call.arguments()!!))
      } catch (error: FlutterError) {
        return result.error(error.code, error.message, error.details)
      } catch (error: Throwable) {
        return result.error("INVALID_ARGS", "invalid arguments for session", null)
      }
    } else {
      null
    }

    CoroutineScope(Dispatchers.Default).launch {
      try {
        when (call.method) {
          "_init" -> {
            cleanUp()
            result.success(true)
          }
          "getTemporaryDirectory" -> result.success(getTemporaryDirectory())
          "getAvailableDiskSpace" -> result.success(getAvailableDiskSpace())
          "deleteFile" -> result.success(emptyResponse(deleteFile(DeleteFileArgs.parse(call))))
          "checkCropVideoDiskSpace" -> result.success(emptyResponse(checkCropVideoDiskSpace(CropVideoArgs.parse(call))))
          "startCropVideo" -> result.success(startCropVideo(CropVideoArgs.parse(call)))
          "awaitCropVideo" -> result.success(awaitCropVideo(awaitedSession!!))
          else -> result.notImplemented()
        }
      } catch (error: FlutterError) {
        result.error(error.code, error.message, error.details)
      } catch (error: Throwable) {
        result.error("UNKNOWN_ERR", "unknown error", error.stackTraceToString())
      }
    }
  }

  internal data class DeleteFileArgs(val path: String) {

    companion object {
      fun parse(call: MethodCall): DeleteFileArgs {
        try {
          val path = call.argument<String>("path")

          if (path.isNullOrBlank()) {
            throw FlutterError(code = "INVALID_PATH", message = "invalid path specified for deleteFile")
          }

          return DeleteFileArgs(path)
        } catch (_: ClassCastException) {
          throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for deleteFile")
        }
      }
    }

  }

  internal data class SessionArgs(val sessionId: String) {

    companion object {
      fun parse(arguments: Map<*, *>): SessionArgs {
        val sessionId: String = (arguments["sessionId"] as? String)
          ?: throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for session")

        return SessionArgs(sessionId)
      }
    }

  }

  internal sealed class CropVideoQuality(open val rawValue: String) {
    data object PresetHD : CropVideoQuality("presetHD")
    data object PresetFullHD : CropVideoQuality("presetFullHD")
    data object Highest : CropVideoQuality("highest")
    data object Passthrough : CropVideoQuality("passthrough")

    data class Unknown(override val rawValue: String) : CropVideoQuality(rawValue)

    companion object {
      /** The default is a stream copy, as on iOS. */
      val default = Passthrough

      val values = arrayOf(PresetHD, PresetFullHD, Highest, Passthrough)

      fun parse(value: String?): CropVideoQuality {
        if (value == null || value == "default") {
          return default
        }

        for (parsedValue in values) {
          if (parsedValue.rawValue == value) {
            return parsedValue
          }
        }

        return Unknown(value)
      }
    }
  }

  internal data class CropVideoArgs(val path: String, val start: Long, val end: Long, val quality: CropVideoQuality) {

    companion object {
      fun parse(call: MethodCall): CropVideoArgs {
        val args = try {
          val rawStart = call.argument<Any>("start")!!
          val rawEnd = call.argument<Any>("end")!!

          CropVideoArgs(
            path = call.argument<String>("path")!!,
            start = rawStart as? Long ?: (rawStart as Int).toLong(),
            end = rawEnd as? Long ?: (rawEnd as Int).toLong(),
            quality = CropVideoQuality.parse(call.argument<String?>("quality"))
          )
        } catch (_: Exception) {
          throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for cropVideo")
        }

        // An unrecognised quality is rejected, as on iOS.
        if (args.quality is CropVideoQuality.Unknown) {
          throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for cropVideo: unknown quality '${args.quality.rawValue}'")
        }

        if (args.start > args.end) {
          throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for cropVideo: 'start' must not be after 'end'")
        }

        return args
      }
    }

  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, kChannelName)
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "$kChannelName/$eventChannelId")
    eventChannel.setStreamHandler(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding)
          = onAttachedToActivity(binding)

  override fun onDetachedFromActivity() = channel.setMethodCallHandler(null)
  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    onDetachedFromActivity()
    cleanUp()
  }

}
