package xyz.apollosoftware.amphitheatre

import android.app.Activity
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.stubbing.Answer
import org.mockito.stubbing.OngoingStubbing
import java.io.File
import java.net.URLClassLoader
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

internal class AmphitheatrePluginTest {
  private lateinit var plugin: AmphitheatrePlugin
  private lateinit var mockActivity: Activity
  private lateinit var mockBinding: ActivityPluginBinding

  @BeforeEach
  fun prepareTests() {
    plugin = AmphitheatrePlugin()
    mockActivity = mock(Activity::class.java)
    mockBinding = mock(ActivityPluginBinding::class.java)
    upon(mockBinding.activity).thenReturn(mockActivity)
    plugin.onAttachedToActivity(mockBinding)
  }

  /**
   * A [MethodChannel.Result] that can be awaited: the plugin answers method calls from a coroutine
   * on `Dispatchers.Default`, after `onMethodCall` has returned, so a test has to wait for the answer
   * before verifying it.
   */
  private class AwaitableResult {
    val mock: MethodChannel.Result = mock(MethodChannel.Result::class.java)
    private val answered = CountDownLatch(1)

    init {
      val countDown = Answer<Any?> { answered.countDown(); null }
      doAnswer(countDown).`when`(mock).success(any())
      doAnswer(countDown).`when`(mock).error(anyString(), any(), any())
      doAnswer(countDown).`when`(mock).notImplemented()
    }

    fun await() {
      assertTrue(answered.await(5, TimeUnit.SECONDS), "the method call was not answered in time")
    }
  }

  /** Invokes [call] on the plugin and waits for its answer. */
  private fun invoke(call: MethodCall): MethodChannel.Result {
    val result = AwaitableResult()
    plugin.onMethodCall(call, result.mock)
    result.await()
    return result.mock
  }

  @Test
  fun handlesUnboundActivity() {
    // Rebuild the test mocks so that we get a fresh AmphitheatrePlugin instance where the
    // mockActivity has not yet been bound.
    plugin = AmphitheatrePlugin()
    mockActivity = mock(Activity::class.java)
    upon(mockBinding.activity).thenReturn(mockActivity)

    val call = MethodCall("anything__thisIsNotARealAction", null)

    val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    verify(mockResult).error("ERR_BAD_ACCESS", "There is no activity to bind the action to.", null)
  }

  @Test
  fun unknownMethod_isNotImplemented() {
    val result = invoke(MethodCall("anything__thisIsNotARealAction", null))

    verify(result).notImplemented()
  }

  @Test
  fun getTemporaryDirectory_returnsExpectedValue() {
    // A real directory: the plugin creates its own directory inside the cache directory.
    val cacheDir = Files.createTempDirectory("amphitheatre").toFile()
    upon(mockActivity.cacheDir).thenReturn(cacheDir)

    val result = invoke(MethodCall("getTemporaryDirectory", null))

    verify(result).success(File(cacheDir, kChannelName).absolutePath)
    assertTrue(File(cacheDir, kChannelName).isDirectory)
    File(cacheDir, kChannelName).delete()
    cacheDir.delete()
  }

  @Test
  fun startCropVideo_handlesIllegalArguments() {
    fun createCall(args: Map<String, Any?>?) = MethodCall("startCropVideo", args)

    val results = listOf(
      invoke(createCall(null)),
      invoke(createCall(mapOf("foo" to "bar"))),
      invoke(createCall(mapOf("path" to null, "start" to 1, "end" to 2))),
      invoke(createCall(mapOf("path" to "/foo/bar", "start" to null, "end" to 2))),
      invoke(createCall(mapOf("path" to "/foo/bar", "start" to 1, "end" to null))),
      invoke(createCall(mapOf("path" to "/foo/bar", "start" to null, "end" to null))),
    )

    for (result in results) {
      verify(result).error("INVALID_ARGS", "invalid arguments for cropVideo", null)
    }
  }

  @Test
  fun startCropVideo_rejectsAnUnknownQuality() {
    val result = invoke(MethodCall("startCropVideo", mapOf("path" to "/foo/bar", "start" to 1, "end" to 2, "quality" to "4k")))

    verify(result).error("INVALID_ARGS", "invalid arguments for cropVideo: unknown quality '4k'", null)
  }

  @Test
  fun startCropVideo_rejectsAStartAfterTheEnd() {
    val result = invoke(MethodCall("startCropVideo", mapOf("path" to "/foo/bar", "start" to 3, "end" to 2)))

    verify(result).error("INVALID_ARGS", "invalid arguments for cropVideo: 'start' must not be after 'end'", null)
  }

  @Test
  fun checkCropVideoDiskSpace_handlesIllegalArguments() {
    val result = invoke(MethodCall("checkCropVideoDiskSpace", mapOf("path" to "/foo/bar", "start" to 1)))

    verify(result).error("INVALID_ARGS", "invalid arguments for cropVideo", null)
  }

  @Test
  fun getThumbnails_handlesIllegalArguments() {
    fun createCall(args: Map<String, Any?>?) = MethodCall("getThumbnails", args)

    val missing = listOf(
      invoke(createCall(null)),
      invoke(createCall(mapOf("path" to "/foo/bar"))),
      invoke(createCall(mapOf("path" to "/foo/bar", "count" to 3))),
      invoke(createCall(mapOf("path" to null, "count" to 3, "maxHeight" to 64))),
    )
    for (result in missing) {
      verify(result).error("INVALID_ARGS", "invalid arguments for getThumbnails", null)
    }

    val nonPositive = listOf(
      invoke(createCall(mapOf("path" to "/foo/bar", "count" to 0, "maxHeight" to 64))),
      invoke(createCall(mapOf("path" to "/foo/bar", "count" to 3, "maxHeight" to 0))),
    )
    for (result in nonPositive) {
      verify(result).error(
        "INVALID_ARGS",
        "invalid arguments for getThumbnails: 'count' and 'maxHeight' must be positive",
        null,
      )
    }
  }

  @Test
  fun getThumbnails_reportsAMissingFile() {
    val result = invoke(MethodCall("getThumbnails", mapOf("path" to "/does/not/exist.mp4", "count" to 3, "maxHeight" to 64)))

    verify(result).error("SEARCH_FAIL", "Failed to locate the provided file.", null)
  }

  @Test
  fun getThumbnailsArgs_clampsCountAndMaxHeight() {
    val args = AmphitheatrePlugin.GetThumbnailsArgs.parse(
      MethodCall("getThumbnails", mapOf("path" to "/foo/bar", "count" to 500, "maxHeight" to 4000)),
    )

    assertEquals(AmphitheatrePlugin.GetThumbnailsArgs("/foo/bar", 50, 1080), args)
  }

  @Test
  fun getThumbnailsArgs_acceptsAnyNumber() {
    // The channel codec delivers Int, Long or Double depending on the Dart value.
    val fromLong = AmphitheatrePlugin.GetThumbnailsArgs.parse(
      MethodCall("getThumbnails", mapOf("path" to "/foo/bar", "count" to 3L, "maxHeight" to 64L)),
    )
    val fromDouble = AmphitheatrePlugin.GetThumbnailsArgs.parse(
      MethodCall("getThumbnails", mapOf("path" to "/foo/bar", "count" to 3.0, "maxHeight" to 64.0)),
    )

    assertEquals(AmphitheatrePlugin.GetThumbnailsArgs("/foo/bar", 3, 64), fromLong)
    assertEquals(AmphitheatrePlugin.GetThumbnailsArgs("/foo/bar", 3, 64), fromDouble)
  }

  @Test
  fun cropVideoQuality_isUsableWhenFirstReachedThroughAnObject() {
    // The classes are loaded afresh, so the order in which the other tests touched them does not
    // matter: here one of the objects is initialised first, which starts the sealed class's own
    // initialisation while the object's is still in progress. Companion fields assigned there
    // captured null; getters do not.
    val classPath = System.getProperty("java.class.path").split(File.pathSeparator)
      .map { File(it).toURI().toURL() }.toTypedArray()
    val loader = URLClassLoader(classPath, null)
    val prefix = "xyz.apollosoftware.amphitheatre.AmphitheatrePlugin\$CropVideoQuality"

    val passthrough = Class.forName("$prefix\$Passthrough", true, loader).getField("INSTANCE").get(null)
    val presetHD = Class.forName("$prefix\$PresetHD", true, loader).getField("INSTANCE").get(null)
    val companion = Class.forName(prefix, true, loader).getField("Companion").get(null)
    val parse = companion.javaClass.getMethod("parse", String::class.java)

    assertTrue(parse.invoke(companion, null) === passthrough, "the default quality must be passthrough")
    assertTrue(parse.invoke(companion, "presetHD") === presetHD, "a named quality must resolve to its object")
    val unknown = parse.invoke(companion, "4k")
    assertTrue(unknown != null && unknown.javaClass.simpleName == "Unknown", "an unrecognised quality must be Unknown")
    loader.close()
  }

  @Test
  fun awaitCropVideo_rejectsAnUnknownSession() {
    val result = invoke(MethodCall("awaitCropVideo", mapOf("sessionId" to "nope")))

    verify(result).error("UNKNOWN_SESSION", "invalid session ID", "nope")
  }

  @Test
  fun cancelCropVideo_ignoresAnUnknownSession() {
    val result = invoke(MethodCall("cancelCropVideo", mapOf("sessionId" to "nope")))

    verify(result).success(null)
  }

  @Test
  fun cancelCropVideo_handlesIllegalArguments() {
    val results = listOf(
      invoke(MethodCall("cancelCropVideo", null)),
      invoke(MethodCall("cancelCropVideo", mapOf("foo" to "bar"))),
    )

    for (result in results) {
      verify(result).error("INVALID_ARGS", "invalid arguments for session", null)
    }
  }

  /** Not a fan of the backticks... See [Mockito.when] */
  private fun <T> upon(methodCall: T): OngoingStubbing<T> = Mockito.`when`(methodCall)
}
