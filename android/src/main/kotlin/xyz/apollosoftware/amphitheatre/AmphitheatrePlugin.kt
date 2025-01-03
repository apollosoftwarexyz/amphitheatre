package xyz.apollosoftware.amphitheatre

import android.app.Activity
import android.media.MediaCodec
import android.media.MediaCodec.BUFFER_FLAG_CODEC_CONFIG
import android.media.MediaCodec.BUFFER_FLAG_KEY_FRAME
import android.media.MediaCodec.BUFFER_FLAG_PARTIAL_FRAME
import android.media.MediaCodec.BufferInfo
import android.media.MediaExtractor
import android.media.MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME
import android.media.MediaExtractor.SAMPLE_FLAG_SYNC
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaMuxer.OutputFormat
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import kotlin.math.min

const val kChannelName = "xyz.apollosoftware.amphitheatre"

/** AmphitheatrePlugin */
class AmphitheatrePlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /** The MethodChannel that will handle communication between Flutter and Android. */
  private lateinit var channel: MethodChannel

  /** The Activity that the application is currently bound to. */
  private var activity: Activity? = null

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (activity == null) {
      return result.error("ERR_BAD_ACCESS", "There is no activity to bind the action to.", null)
    }

    try {
      when(call.method) {
        "getTemporaryDirectory" -> {
          // Create the cache directory if it does not already exist.
          val cacheDirBase = activity!!.cacheDir
          val cacheDir = File(cacheDirBase.absolutePath, kChannelName)
          if (!cacheDir.exists()) cacheDir.mkdirs()
          result.success(cacheDir.absolutePath)
          return
        }
        "cropVideo" -> {
          val (path, start, end) = parseCropVideoArgs(call)
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
                bufferSize = min(format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), bufferSize)
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
    } catch (_: IllegalMethodCallArguments) {
      result.error("ERR_BAD_PARAMS", "Invalid parameters supplied to ${call.method}()", null)
    }
  }

  private fun parseCropVideoArgs(call: MethodCall): Triple<String, Long, Long> {
    try {
      val path = call.argument<String>("path")!!
      val rawStart = call.argument<Any>("start")!!
      val rawEnd = call.argument<Any>("end")!!

      val start: Long = if (rawStart is Long) rawStart else (rawStart as Int).toLong()
      val end: Long = if (rawEnd is Long) rawEnd else (rawEnd as Int).toLong()
      return Triple(path, start, end)
    } catch (ex: Exception) {
      when (ex) {
        is ClassCastException, is NullPointerException ->
          throw IllegalMethodCallArguments()
        else -> throw ex
      }
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, kChannelName)
    channel.setMethodCallHandler(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding)
          = onAttachedToActivity(binding)

  override fun onDetachedFromActivity() = channel.setMethodCallHandler(null)
  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding)
          = onDetachedFromActivity()

}

class IllegalMethodCallArguments: Exception()
