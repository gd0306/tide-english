package cn.gd306.tideenglish.network
import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
class ProviderTeachingClientTest {
 @Test fun selectedProviderAndModelAreSentWithoutRedirects()=runBlocking {
  var request: Request?=null
  val http=OkHttpClient.Builder().addInterceptor { chain -> request=chain.request(); Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("""{"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"hello"}}]}""".toResponseBody()).build() }.build()
  val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.DEEPSEEK,"my-model")},{"synthetic-key"},http)
  assertEquals("hello",client.respond("Teach","hi").text)
  assertEquals("api.deepseek.com",request!!.url.host)
  val buffer=okio.Buffer(); request!!.body!!.writeTo(buffer)
  assertEquals("my-model",Json.parseToJsonElement(buffer.readUtf8()).jsonObject["model"]!!.jsonPrimitive.content)
 }
 @Test fun refusesTruncatedAndRedactsProviderErrors()=runBlocking {
  for ((code,body) in listOf(200 to """{"choices":[{"index":0,"finish_reason":"length","message":{"role":"assistant","content":"partial"}}]}""",401 to "secret-provider-diagnostic")) {
   val http=OkHttpClient.Builder().addInterceptor { c -> Response.Builder().request(c.request()).protocol(Protocol.HTTP_1_1).code(code).message("OK").body(body.toResponseBody()).build() }.build()
   val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.GLM)},{"synthetic-key"},http)
   val error=runCatching { client.respond("Teach","hi") }.exceptionOrNull()
   assertNotNull(error); assertFalse(error!!.message.orEmpty().contains("secret")); assertFalse(error.message.orEmpty().contains("partial"))
  }
 }
 @Test fun unsupportedSearchFailsBeforeAnyNetworkRequest()=runBlocking {
  val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.DEEPSEEK)},{"synthetic-key"})
  val error=runCatching { client.respond("Teach","news",search=true) }.exceptionOrNull()
  assertTrue(error?.message.orEmpty().contains("search",ignoreCase=true))
 }
 @Test fun authenticatedRedirectIsNeverFollowed()=runBlocking {
  val server=okhttp3.mockwebserver.MockWebServer()
  server.start()
  try {
   server.enqueue(okhttp3.mockwebserver.MockResponse().setResponseCode(302).addHeader("Location",server.url("/stolen")))
   server.enqueue(okhttp3.mockwebserver.MockResponse().setBody("unexpected redirect"))
   val http=OkHttpClient.Builder().addInterceptor { chain -> chain.proceed(chain.request().newBuilder().url(server.url("/chat/completions")).build()) }.build()
   val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.DEEPSEEK)},{"synthetic-key"},http)
   assertNotNull(runCatching { client.respond("Teach","hi") }.exceptionOrNull())
   assertEquals(1,server.requestCount)
  } finally { server.shutdown() }
 }
 @Test fun openAIUsesSelectedResponsesModelAndSearch()=runBlocking {
  var request:Request?=null
  val http=OkHttpClient.Builder().addInterceptor { chain ->
   request=chain.request()
   Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("""{"status":"completed","output":[{"content":[{"type":"output_text","text":"hello"}]}]}""".toResponseBody()).build()
  }.build()
  val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.OPENAI,"chosen-chat")},{"synthetic-key"},http)
  assertEquals("hello",client.respond("Teach","hi",search=true).text)
  assertEquals("/v1/responses",request!!.url.encodedPath)
  val buffer=okio.Buffer();request!!.body!!.writeTo(buffer)
  val body=Json.parseToJsonElement(buffer.readUtf8()).jsonObject
  assertEquals("chosen-chat",body["model"]!!.jsonPrimitive.content)
  assertEquals("web_search",body["tools"]!!.jsonArray.first().jsonObject["type"]!!.jsonPrimitive.content)
 }
 @Test fun exposesOnlyAllowlistedFailureClassification()=runBlocking {
  val http=OkHttpClient.Builder().addInterceptor { chain ->
   Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(429).message("Limit").body("""{"error":{"code":"insufficient_quota","message":"raw-secret-diagnostic"}}""".toResponseBody()).build()
  }.build()
  val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.DEEPSEEK)},{"synthetic-key"},http)
  val error=runCatching { client.respond("Teach","hi") }.exceptionOrNull() as ProviderTeachingClient.ProviderException
  assertEquals(429,error.status)
  assertEquals(ProviderFailureKind.quota,error.kind)
  assertFalse(error.message.orEmpty().contains("raw-secret"))
 }
 @Test fun compatibleMeaningStreamsDeltasAndRequiresTerminalCompletion()=runBlocking {
  val events="""data: {"choices":[{"index":0,"delta":{"content":"Good"},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{"content":" morning"},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

"""
  for(complete in listOf(true,false)) {
   val http=OkHttpClient.Builder().addInterceptor { chain -> Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").header("Content-Type","text/event-stream").body((if(complete) events else events.substringBefore("data: [DONE]")).toResponseBody()).build() }.build()
   val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.DEEPSEEK)},{"synthetic-key"},http)
   val updates=mutableListOf<String>()
   val result=runCatching { client.streamMeaning("Translate","morning") { updates+=it } }
   assertEquals(listOf("Good","Good morning"),updates)
   if(complete) assertEquals("Good morning",result.getOrThrow().text) else assertTrue(result.isFailure)
  }
 }
 @Test fun openAIMeaningUsesResponsesStreamAndFinalResult()=runBlocking {
  var request:Request?=null
  val events="""data: {"type":"response.output_text.delta","delta":"Hello"}

data: {"type":"response.completed","response":{"status":"completed","output":[{"content":[{"type":"output_text","text":"Hello"}]}]}}

"""
  val http=OkHttpClient.Builder().addInterceptor { chain -> request=chain.request();Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").header("Content-Type","text/event-stream").body(events.toResponseBody()).build() }.build()
  val client=ProviderTeachingClient({ProviderConfiguration(ModelProvider.OPENAI,"chosen-model")},{"synthetic-key"},http)
  val updates=mutableListOf<String>()
  assertEquals("Hello",client.streamMeaning("Translate","hello") { updates+=it }.text)
  assertEquals(listOf("Hello"),updates)
  assertEquals("/v1/responses",request!!.url.encodedPath)
 }
}
