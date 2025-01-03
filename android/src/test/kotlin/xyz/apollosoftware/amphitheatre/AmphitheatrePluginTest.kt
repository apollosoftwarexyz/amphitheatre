package xyz.apollosoftware.amphitheatre

import android.app.Activity
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.jupiter.api.BeforeEach
import org.mockito.Mockito
import org.mockito.Mockito.mock
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.stubbing.OngoingStubbing
import java.io.File
import kotlin.test.Test

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
  fun getTemporaryDirectory_returnsExpectedValue() {
    val call = MethodCall("getTemporaryDirectory", null)

    upon(mockActivity.cacheDir).thenReturn(File("/foo/bar/cache"))

    val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    verify(mockResult).success("/foo/bar/cache/${kChannelName}")
  }

  @Test
  fun cropVideo_handlesIllegalArguments() {
    val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)
    fun createCall(args: Map<String, Any?>?) = MethodCall("cropVideo", args)

    plugin.onMethodCall(createCall(null), mockResult)
    plugin.onMethodCall(createCall(mapOf("foo" to "bar")), mockResult)
    plugin.onMethodCall(createCall(mapOf("path" to null, "start" to 1, "end" to 2)), mockResult)
    plugin.onMethodCall(createCall(mapOf("path" to "/foo/bar", "start" to null, "end" to 2)), mockResult)
    plugin.onMethodCall(createCall(mapOf("path" to "/foo/bar", "start" to 1, "end" to null)), mockResult)
    plugin.onMethodCall(createCall(mapOf("path" to "/foo/bar", "start" to null, "end" to null)), mockResult)

    verify(mockResult, times(6)).error("ERR_BAD_PARAMS", "Invalid parameters supplied to cropVideo()", null)
  }

  /** Not a fan of the backticks... See [Mockito.when] */
  private fun <T> upon(methodCall: T): OngoingStubbing<T> = Mockito.`when`(methodCall)
}
