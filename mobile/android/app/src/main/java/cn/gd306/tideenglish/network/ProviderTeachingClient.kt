package cn.gd306.tideenglish.network

import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderFailureKind
import cn.gd306.tideenglish.core.ProviderConfiguration
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.Buffer

/** Every helper reads one immutable recipient/model snapshot per request. */
class ProviderTeachingClient(
 private val configuration: () -> ProviderConfiguration,
 private val credential: (ProviderConfiguration) -> String?,
 client: OkHttpClient = OkHttpClient.Builder().connectTimeout(45,TimeUnit.SECONDS).readTimeout(60,TimeUnit.SECONDS).callTimeout(60,TimeUnit.SECONDS).build(),
):TeachingClient {
 private val client=client.newBuilder().followRedirects(false).followSslRedirects(false).cookieJar(CookieJar.NO_COOKIES).cache(null).build()
 override suspend fun respond(instructions:String,input:String,schema:JsonObject?,search:Boolean,purpose:HelperPurpose?):APIResult {
  val config=configuration().validated()
  if(search && config.provider !in listOf(ModelProvider.OPENAI,ModelProvider.GLM)) throw ProviderException("This provider does not support current-topic search. Select OpenAI or GLM to search.")
  val key=credential(config)?.let { ProviderConfiguration.validatedCredential(it) } ?: throw APIClient.APIException.MissingKey
  val body=payload(config,instructions,input,schema,search)
  val request=Request.Builder().url((config.baseURL+if(config.provider==ModelProvider.OPENAI) "/responses" else "/chat/completions").toHttpUrl()).header("Authorization","Bearer $key").post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build()
  val value=execute(request)
  if(configuration().validated()!=config) throw kotlinx.coroutines.CancellationException("Provider selection changed.")
  if(config.provider==ModelProvider.OPENAI) return decodeTeachingResponse(value)
  val choices=value["choices"] as? JsonArray ?: throw ProviderException(INCOMPLETE)
  if(choices.size!=1 || value["error"]!=null) throw ProviderException(INCOMPLETE)
  val choice=choices.firstOrNull() as? JsonObject ?: throw ProviderException(INCOMPLETE)
  val message=choice["message"] as? JsonObject ?: throw ProviderException(INCOMPLETE)
  if(choice["index"]!=JsonPrimitive(0) || message["role"]!=JsonPrimitive("assistant")) throw ProviderException(INCOMPLETE)
  if(message["refusal"] !in listOf(null,JsonNull)) throw ProviderException("This request could not be completed. Try another topic.")
  if(choice["finish_reason"]?.jsonPrimitive?.contentOrNull!="stop") throw ProviderException(INCOMPLETE)
  if((message["tool_calls"] as? JsonArray)?.isNotEmpty()==true) throw ProviderException(INCOMPLETE)
  val text=(message["content"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull?.takeIf { it.isNotBlank() } ?: throw ProviderException(INCOMPLETE)
  if(text.toByteArray().size>65536) throw ProviderException(INCOMPLETE)
  if(schema!=null && runCatching { matchesProviderSchema(Json.parseToJsonElement(text),schema) }.getOrDefault(false)==false) throw ProviderException(INCOMPLETE)
  val usage=value["usage"] as? JsonObject
  val sources=(value["web_search"] as? JsonArray).orEmpty().take(50).mapNotNull { item ->
   val obj=item as? JsonObject ?: return@mapNotNull null
   val url=obj.str("link") ?: return@mapNotNull null
   val uri=runCatching { java.net.URI(url) }.getOrNull() ?: return@mapNotNull null
   if(url.length>2048 || uri.scheme!="https" || uri.host.isNullOrEmpty() || uri.userInfo!=null) return@mapNotNull null
   cn.gd306.tideenglish.core.SourceLink(obj.str("title")?.take(300) ?: "Source",url)
  }.distinctBy { it.url }
  return APIResult(text,sources,APIUsage((usage?.get("prompt_tokens") as? JsonPrimitive)?.intOrNull?.coerceIn(0,1_000_000_000) ?: 0,(usage?.get("completion_tokens") as? JsonPrimitive)?.intOrNull?.coerceIn(0,1_000_000_000) ?: 0,if(sources.isEmpty()) 0 else 1))
 }
 private fun payload(config:ProviderConfiguration,instructions:String,input:String,schema:JsonObject?,search:Boolean):JsonObject {
  return if(config.provider==ModelProvider.OPENAI) buildJsonObject {
   put("model",config.model);put("store",false);put("instructions",instructions)
   put("input",buildJsonArray { add(buildJsonObject { put("role","user");put("content",input) }) })
   put("max_output_tokens",if(schema==null) 1400 else 2200)
   put("reasoning",buildJsonObject { put("effort","low") })
   if(schema!=null) put("text",buildJsonObject { put("format",buildJsonObject { put("type","json_schema");put("name","tideenglish_result");put("strict",true);put("schema",schema) }) })
   if(search) { put("tools",buildJsonArray { add(buildJsonObject { put("type","web_search") }) });put("tool_choice","auto");put("max_tool_calls",1) }
  } else buildJsonObject {
   put("model",config.model)
   put("messages",buildJsonArray {
    add(buildJsonObject { put("role","system"); put("content",instructions + if(schema!=null) "\nReturn only JSON matching this schema: $schema" else "") })
    add(buildJsonObject { put("role","user"); put("content",input) })
   })
   if(config.provider!=ModelProvider.OPENAI) put("max_tokens",if(schema==null) 1400 else 2200)
   if(schema!=null) put("response_format",buildJsonObject { put("type","json_object") })
   if(config.provider==ModelProvider.DEEPSEEK || (config.provider==ModelProvider.GLM && listOf("glm-4.5","glm-4.6","glm-4.7","glm-5","glm-5.1","glm-5.2").any { config.model==it || config.model.startsWith("$it-") })) put("thinking",buildJsonObject { put("type","disabled") })
   if(search) { put("tools",buildJsonArray { add(buildJsonObject { put("type","web_search");put("web_search",buildJsonObject { put("enable",true);put("search_engine","search_pro");put("search_result",true) }) }) });put("tool_choice","auto") }
  }
 }
 override suspend fun streamMeaning(instructions:String,input:String,onText:(String)->Unit):APIResult {
  val config=configuration().validated()
  val key=credential(config)?.let { ProviderConfiguration.validatedCredential(it) } ?: throw APIClient.APIException.MissingKey
  val body=buildJsonObject {
   payload(config,instructions,input,null,false).forEach { (name,value) -> put(name,value) }
   put("stream",true)
   if(config.provider!=ModelProvider.OPENAI) put("stream_options",buildJsonObject { put("include_usage",true) })
  }
  val request=Request.Builder().url((config.baseURL+if(config.provider==ModelProvider.OPENAI) "/responses" else "/chat/completions").toHttpUrl()).header("Authorization","Bearer $key").header("Accept","text/event-stream").post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build()
  val callbacks=currentCoroutineContext().minusKey(Job)
  fun current() { if(configuration().validated()!=config) throw CancellationException("Provider selection changed.") }
  try {
   return streamingResponse(client,request) { response ->
    if(!response.isSuccessful) throw httpFailure(response)
    if(response.header("Content-Type")?.startsWith("text/event-stream",ignoreCase=true)!=true) throw ProviderException(INCOMPLETE)
    var text=""
    if(config.provider==ModelProvider.OPENAI) {
     val result=readTextEvents(response) { event ->
      current()
      when(event.str("type")) {
       "response.output_text.delta" -> { text+=event.str("delta") ?: throw ProviderException(INCOMPLETE);if(text.toByteArray().size>65536) throw ProviderException(INCOMPLETE);withContext(callbacks) { current();onText(text) };null }
       "response.completed" -> event["response"] as? JsonObject ?: throw ProviderException(INCOMPLETE)
       "response.refusal.delta","response.refusal.done" -> throw ProviderException("This request could not be completed. Try another topic.")
       "error","response.failed","response.incomplete" -> throw ProviderException(INCOMPLETE)
       else -> null
      }
     }
     current();decodeTeachingResponse(result)
    } else {
     val source=response.body?.source() ?: throw ProviderException(INCOMPLETE)
     val data=StringBuilder();var total=0L;var finished=false;var terminal=false;var usage:JsonObject?=null
     while(!source.exhausted()) {
      currentCoroutineContext().ensureActive();current()
      val line=source.readUtf8LineStrict(65536);total+=line.toByteArray().size+1; if(total>2097152) throw ProviderException(INCOMPLETE)
      if(line.isEmpty()) {
       if(data.isEmpty()) continue
       val eventText=data.toString();data.clear()
       if(eventText=="[DONE]") { terminal=true;break }
       val event=Json.parseToJsonElement(eventText).jsonObject
       if(event["error"]!=null) throw ProviderException(INCOMPLETE)
       (event["usage"] as? JsonObject)?.let { usage=it }
       val choices=event["choices"] as? JsonArray ?: throw ProviderException(INCOMPLETE)
       if(choices.isEmpty()) continue
       if(choices.size!=1) throw ProviderException(INCOMPLETE)
       val choice=choices[0].jsonObject
       if(choice["index"]!=JsonPrimitive(0)) throw ProviderException(INCOMPLETE)
       val delta=choice["delta"] as? JsonObject ?: throw ProviderException(INCOMPLETE)
       if(delta["refusal"] !in listOf(null,JsonNull)) throw ProviderException("This request could not be completed. Try another topic.")
       if((delta["tool_calls"] as? JsonArray)?.isNotEmpty()==true) throw ProviderException(INCOMPLETE)
       delta.str("content")?.let { value -> if(finished) throw ProviderException(INCOMPLETE);text+=value;if(text.toByteArray().size>65536) throw ProviderException(INCOMPLETE);withContext(callbacks) { current();onText(text) } }
       val finish=(choice["finish_reason"] as? JsonPrimitive)?.contentOrNull
       if(finish!=null) { if(finish!="stop") throw ProviderException(INCOMPLETE);finished=true }
      } else if(line.startsWith("data:")) {
       if(data.isNotEmpty()) data.append('\n');data.append(line.removePrefix("data:").removePrefix(" "))
       if(data.toString().toByteArray().size>65536) throw ProviderException(INCOMPLETE)
      }
     }
     if(!terminal || !finished || text.isBlank()) throw ProviderException(INCOMPLETE)
     current();APIResult(text,emptyList(),APIUsage((usage?.get("prompt_tokens") as? JsonPrimitive)?.intOrNull?.coerceIn(0,1000000000) ?: 0,(usage?.get("completion_tokens") as? JsonPrimitive)?.intOrNull?.coerceIn(0,1000000000) ?: 0))
    }
   }
  } catch(e:CancellationException) { throw e }
  catch(e:APIClient.APIException.Refused) { throw ProviderException("This request could not be completed. Try another topic.") }
  catch(e:ProviderException) { throw e }
  catch(_:Exception) { throw ProviderException(INCOMPLETE) }
 }
 private suspend fun execute(request:Request):JsonObject = suspendCancellableCoroutine { continuation ->
  val call=client.newCall(request); continuation.invokeOnCancellation { call.cancel() }
  call.enqueue(object:Callback {
   override fun onFailure(call:Call,e:IOException) { if(continuation.isActive) continuation.resumeWithException(ProviderException("The provider could not be reached. Please try again.")) }
   override fun onResponse(call:Call,response:Response) {
    try {
     val result=response.use {
      if(!it.isSuccessful) throw httpFailure(it)
      val body=it.body ?: throw ProviderException(INCOMPLETE)
      if(body.contentLength()>MAX_BYTES) throw ProviderException(INCOMPLETE)
      val buffer=Buffer(); var total=0L
      while(true) { val n=body.source().read(buffer,minOf(8192L,MAX_BYTES+1-total)); if(n==-1L) break; total+=n; if(total>MAX_BYTES) throw ProviderException(INCOMPLETE) }
      try { Json.parseToJsonElement(buffer.readUtf8()).jsonObject } catch (_:Exception) { throw ProviderException(INCOMPLETE) }
     }
     if(continuation.isActive) continuation.resume(result)
    } catch(e:Exception) { if(continuation.isActive) continuation.resumeWithException(if(e is ProviderException) e else ProviderException(INCOMPLETE)) }
   }
  })
 }
 private fun httpFailure(response:Response):ProviderException {
  val code=runCatching {
   val payload=response.peekBody(16385).string()
   if(payload.toByteArray().size>16384) null else (Json.parseToJsonElement(payload).jsonObject["error"] as? JsonObject)?.get("code")?.jsonPrimitive?.contentOrNull
  }.getOrNull()
  return ProviderException(when(response.code) {
   401 -> "This provider did not accept the API key. Check Settings."
   403,404 -> "This API key may not have access to the selected model."
   429 -> "This provider's usage or rate limit was reached."
   else -> "The provider could not complete the request (HTTP ${response.code})."
  },response.code,code)
 }
 class ProviderException(message:String,val status:Int?=null,code:String?=null):IOException(message) {
  val code=ProviderFailureKind.safeCode(code)
  val kind:ProviderFailureKind get()=status?.let { ProviderFailureKind.classify(it,this.code) } ?: ProviderFailureKind.unavailable
 }
 companion object { private const val MAX_BYTES=1_048_576L; private const val INCOMPLETE="The provider returned an incomplete response. Please try again." }
}
