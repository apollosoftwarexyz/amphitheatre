package xyz.apollosoftware.amphitheatre

import android.app.Activity
import android.media.MediaCodec.BufferInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaMuxer.OutputFormat
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

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
 * @param sink The event sink for the export session - where progress updates should be delivered.
 */
internal class AmphitheatreExportSession(val activity: Activity, val id: String, val args: AmphitheatrePlugin.CropVideoArgs, var sink: EventChannel.EventSink?) {

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
    // TODO
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

    val args = SessionArgs.parse(arguments)
    val session = sessions[args.sessionId] ?: throw FlutterError(
        code = "UNKNOWN_SESSION",
        message = "invalid session ID",
        details = args.sessionId
    )

    session.bind(sink)
  }

  override fun onCancel(arguments: Any?) {
    if (arguments == null) return

    val args = SessionArgs.parse(arguments)
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

  fun getTemporaryDirectory(result: Result) {
    // Create the cache directory if it does not already exist.
    val cacheDir = File(activity!!.cacheDir.absolutePath, kChannelName)
    if (!cacheDir.exists()) cacheDir.mkdirs()
    result.success(cacheDir.absolutePath)
  }

  fun deleteFile(call: MethodCall) {
    val (path) = DeleteFileArgs.parse(call)
    File(path).delete()
  }

  fun getAvailableDiskSpace(result: Result) {
    try {
      result.success(StatFs(activity!!.cacheDir.absolutePath).availableBytes)
    } catch (_: Throwable) {
      throw FlutterError(code = "GET_AVAILABLE_DISK_SPACE_FAILED", message = "failed to determine number of available bytes on disk")
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (activity == null) {
      return result.error("ERR_BAD_ACCESS", "There is no activity to bind the action to.", null)
    }

    try {
      when(call.method) {
        "_init" -> {
          cleanUp()
          result.success(true)
          return
        }
        "getTemporaryDirectory" -> getTemporaryDirectory(result)
        "deleteFile" -> deleteFile(call)
        "getAvailableDiskSpace" -> getAvailableDiskSpace(result)
        "cropVideo" -> {
          val (path, start, end) = CropVideoArgs.parse(call)
          val inputFile = File(path)

          // Make sure the input file exists. Returning the same error if the input file is a
          // directory (instead of a file, as expected) mirrors the semantics of the iOS
          // implementation.
          if (!inputFile.exists() || inputFile.isDirectory) {
            result.error("ERR_SEARCH_FAIL", "Failed to locate the provided file.", null)
            return
          }

          // Generate the output file path, given the input file path.
          val extension = inputFile.extension
          val hasExtension = extension.isNotEmpty()
          val fileName = inputFile.name
          //  (the baseName is the filename, minus the extension from the end and minus an
          //   additional character for the period proceeding the extension if there is one).
          val baseName = fileName.substring(0, fileName.length - extension.length - (if (hasExtension) 1 else 0))
          val outputFileName = "$baseName.out${if (hasExtension) "." else ""}$extension"
          val outputFile = File(inputFile.parent, outputFileName)

          val extractor = MediaExtractor()
          extractor.setDataSource(path)

          var bufferSize: Int = -1
          val muxer = MediaMuxer(outputFile.absolutePath, OutputFormat.MUXER_OUTPUT_MPEG_4)
          val trackMapping = HashMap<Int, Int>()

          var hasAudioTrack = false
          var hasVideoTrack = false

          (0 until extractor.trackCount).forEach {
            val format = extractor.getTrackFormat(it)
            val mimeType = format.getString(MediaFormat.KEY_MIME) ?: return

            val isAudioTrack = mimeType.startsWith("audio/")
            val isVideoTrack = mimeType.startsWith("video/")

            // Muxing a single audio/ or video/ track is the only thing supported in all SDKs.
            // After SDK 26 (Android O), muxing multiple tracks is supported, so we can allow
            // everything in that case.
            val supported =
              (isAudioTrack && !hasAudioTrack) ||
              (isVideoTrack && !hasVideoTrack) ||
              Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

            if (supported) {
              extractor.selectTrack(it)
              trackMapping[it] = muxer.addTrack(format)

              if (isAudioTrack) hasAudioTrack = true
              if (isVideoTrack) hasVideoTrack = true

              // If there's a limit to the number of bytes that can be used for this track type,
              // ensure it is used for the muxer buffer size. (Otherwise, we can just default to
              // a reasonable size).
              if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                bufferSize = max(format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), bufferSize)
              }
            }
          }

          if (bufferSize < 1) bufferSize = 1024 * 1024 * 8
          val buffer: ByteBuffer = ByteBuffer.allocate(bufferSize)
          val bufferInfo = BufferInfo()

          val metadataRetriever = MediaMetadataRetriever()
          metadataRetriever.setDataSource(path)
          val rotation = metadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)

          var releaseAttempts = 0
          while (releaseAttempts < 3) {
            try {
              metadataRetriever.release()
              break
            } catch (_: IOException) {
              // Thrown when an IOException occurs during MediaMetadataRetriever.release.
              // We'll try up to three times to release it.
              releaseAttempts++
            }
          }

          if (rotation != null) {
            muxer.setOrientationHint(Integer.parseInt(rotation))
          }

          // Seek to the start time.
          extractor.seekTo(start * 1000, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

          try {
            muxer.start()

            while (extractor.sampleTime <= end * 1000) {
              // Read the sample data into the offset of the buffer.
              bufferInfo.offset = 0
              bufferInfo.size = extractor.readSampleData(buffer, bufferInfo.offset)

              // Load attributes from the sample.
              bufferInfo.presentationTimeUs = extractor.sampleTime

              val flags = extractor.sampleFlags
              flags.also { bufferInfo.flags = it }

              muxer.writeSampleData(
                trackMapping[extractor.sampleTrackIndex]!!,
                buffer,
                bufferInfo
              )

              // extractor.advance returns false if there are no more samples left.
              if (!extractor.advance()) break
            }

            muxer.stop()
            muxer.release()
          } catch (ex: Exception) {
            ex.printStackTrace()
            result.error("ERR_FAIL", "The operation failed.", null)
            return
          } finally {
            extractor.release()
          }

          MP4(outputFile.inputStream()).use { mp4 ->
            if (mp4.canBeMadeStreamable) {
              Log.i("AmphitheatrePlugin.MP4", "The MP4 file has been made streamable.")
              mp4.makeStreamable(outputFile)
            }
          }

          inputFile.delete()
          result.success(outputFile.absolutePath)
        }
        else -> result.notImplemented()
      }
    } catch (error: FlutterError) {
      result.error(error.code, error.message, error.details)
    } catch (_: Throwable) {
      result.error("UNKNOWN_ERR", "unknown error", null)
    }
  }

  internal data class DeleteFileArgs(val path: String) {

    companion object {
      fun parse(rawArguments: Any?): DeleteFileArgs {
        var path: String? = null

        val arguments = rawArguments as? Map<*, *>
        if (arguments != null) {
          path = arguments["path"] as? String;
        }

        if (path != null) {
          return DeleteFileArgs(path)
        }

        throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for deleteFile")
      }
    }

  }

  internal data class SessionArgs(val sessionId: String) {

    companion object {
      fun parse(rawArguments: Any?): SessionArgs {
        var sessionId: String? = null

        val arguments = rawArguments as? Map<*, *>
        if (arguments != null) {
          sessionId = arguments["sessionId"] as? String;
        }

        if (sessionId != null) {
          return SessionArgs(sessionId)
        }

        throw FlutterError(code = "INVALID_ARGS", message = "invalid arguments for session")
      }
    }

  }

  internal data class CropVideoArgs(val path: String, val start: Long, val end: Long) {

    companion object {
      fun parse(call: MethodCall): CropVideoArgs {
        try {
          val rawStart = call.argument<Any>("start")!!
          val rawEnd = call.argument<Any>("end")!!

          return CropVideoArgs(
            path = call.argument<String>("path")!!,
            start = rawStart as? Long ?: (rawStart as Int).toLong(),
            end = rawEnd as? Long ?: (rawEnd as Int).toLong()
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
