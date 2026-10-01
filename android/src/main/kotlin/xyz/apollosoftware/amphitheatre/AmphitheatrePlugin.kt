package xyz.apollosoftware.amphitheatre

import android.app.Activity
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.StatFs
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.inspector.MetadataRetriever
import androidx.media3.transformer.Composition
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
import kotlinx.coroutines.guava.await
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
 * @param activity The activity that started the export session.
 * @param id The ID of the session.
 * @param args The arguments that the export session was started with.
 */
@OptIn(UnstableApi::class)
internal class AmphitheatreExportSession(val activity: Activity, val id: String, val args: AmphitheatrePlugin.CropVideoArgs, val transformer: Transformer, val path: String) {

  /**
   * The event sink for the export session - where progress updates should be delivered.
   *
   * This is bound with [bind] on-demand when the Flutter code wishes to receive status updates (by
   * subscribing to the stream).
   */
  var sink: EventChannel.EventSink? = null

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
  }

  /**
   * Deliver the status update to Flutter.
   *
   * @param status The new status to deliver.
   */
  fun notify(status: Any) {
    this.sink?.success(status)
  }

  /**
   * End the event stream bound to the export session (if any).
   */
  fun close() {
    this.sink?.endOfStream()
  }

  /**
   * Cancel the export session.
   */
  fun cancel() {
    Handler(transformer.applicationLooper).post { transformer.cancel() }
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

  /** The set of active export sessions. */
  private var sessions: ConcurrentHashMap<String, AmphitheatreExportSession> = ConcurrentHashMap()

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    if (arguments == null) return

    val args = SessionArgs.parse(arguments as Map<*, *>)
    val session = sessions[args.sessionId] ?: throw FlutterError(
        code = "UNKNOWN_SESSION",
        message = "invalid session ID",
        details = args.sessionId
    )

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
    val (path, start, end) = args

    val cropDurationMs = end - start
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

    if (durationMs == null) {
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

  @OptIn(ExperimentalApi::class, UnstableApi::class)
  internal fun startCropVideo(args: CropVideoArgs): String {
    val (path, start, end) = args

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

    // Generate the output file path, given the input file path.
    val extension = inputFile.extension
    val hasExtension = extension.isNotEmpty()
    val fileName = inputFile.name
    //  (the baseName is the filename, minus the extension from the end and minus an
    //   additional character for the period proceeding the extension if there is one).
    val baseName = fileName.substring(0, fileName.length - extension.length - (if (hasExtension) 1 else 0))
    val outputFileName = "$baseName.out${if (hasExtension) "." else ""}$extension"
    val outputPath = File(inputFile.parent, outputFileName).absolutePath

    val mediaItem = MediaItem.Builder()
      .setUri(path)
      .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
        .setStartPositionMs(start)
        .setEndPositionMs(end)
        .build())
      .build()

    val transformer = Transformer.Builder(activity!!.baseContext)
      .experimentalSetTrimOptimizationEnabled(false)
      .build()

    val session = AmphitheatreExportSession(activity!!, sessionId, args, transformer, outputPath)
    sessions[sessionId] = session

    val progressHolder = ProgressHolder()

    val mainHandler = Handler(transformer.applicationLooper)
    mainHandler.post { transformer.start(mediaItem, outputPath) }

    var started = false
    mainHandler.post(
      object : Runnable {
        override fun run() {
          val state: @ProgressState Int = transformer.getProgress(progressHolder)
          if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
            handleCropVideoProgress(session, progressHolder.progress.toDouble() / 100.0)
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

    return sessionId
  }

  @OptIn(ExperimentalApi::class, UnstableApi::class)
  internal suspend fun awaitCropVideo(args: SessionArgs): String {
    val session = sessions[args.sessionId] ?: throw FlutterError(
      code = "UNKNOWN_SESSION",
      message = "invalid session ID",
      details = args.sessionId
    )

    val result = CompletableDeferred<String>()

    val mainHandler = Handler(session.transformer.applicationLooper)
    mainHandler.post {
      session.transformer.addListener(object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
          val path = sessions.remove(args.sessionId)!!.path

          handleCropVideoProgress(session, 1.0)
          session.close()

          result.complete(path)
        }

        override fun onError(
          composition: Composition,
          exportResult: ExportResult,
          exportException: ExportException
        ) {
          result.completeExceptionally(FlutterError(
            code = "UNEXPECTED_ERROR",
            message = "an unknown error has occurred",
          ))
        }
      })
    }

    return result.await()
  }

  internal fun handleCropVideoProgress(session: AmphitheatreExportSession, progress: Double) {
    session.notify(mapOf(
      "sessionId" to session.id,
      "stage" to "export",
      "quality" to session.args.quality.rawValue,
      "progress" to progress,
    ))
  }

  internal fun emptyResponse(unit: Unit): Any? {
    return null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (activity == null) {
      return result.error("ERR_BAD_ACCESS", "There is no activity to bind the action to.", null)
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
          "awaitCropVideo" -> result.success(awaitCropVideo(SessionArgs.parse(call.arguments()!!)))
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
      val default = PresetFullHD

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
        try {
          val rawStart = call.argument<Any>("start")!!
          val rawEnd = call.argument<Any>("end")!!

          return CropVideoArgs(
            path = call.argument<String>("path")!!,
            start = rawStart as? Long ?: (rawStart as Int).toLong(),
            end = rawEnd as? Long ?: (rawEnd as Int).toLong(),
            quality = CropVideoQuality.parse(call.argument<String?>("quality"))
          )
        } catch (_: Exception) {
          throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for cropVideo")
        }
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
