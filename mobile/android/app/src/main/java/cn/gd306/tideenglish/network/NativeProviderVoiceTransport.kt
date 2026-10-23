package cn.gd306.tideenglish.network

import android.content.Context
import android.os.SystemClock
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderConfiguration
import java.io.IOException
import java.time.Instant
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/** Native GLM/Gemini WebSocket voice. Explicit capability failures permit same-provider local fallback. */
class NativeProviderVoiceTransport(context:Context,private val scope:CoroutineScope,
 private val configuration:()->ProviderConfiguration,private val credential:(ProviderConfiguration)->String?) {
 var onEvent:((JsonObject)->Unit)?=null
 var onFailure:((String)->Unit)?=null
 var onLevels:((Double,Double)->Unit)?=null
 var onCapability:((String)->Unit)?=null
 private val client=OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).cookieJar(CookieJar.NO_COOKIES).cache(null).connectTimeout(20,TimeUnit.SECONDS).readTimeout(0,TimeUnit.SECONDS).build()
 private val audio=NativeRealtimeAudio(context,scope)
 private var socket:WebSocket?=null
 private var state:NativeVoiceProtocol?=null
 private var attempt=0L
 private var began=0L
 private var instructions=""
 private var selected:ProviderConfiguration?=null
 private var startup:CompletableDeferred<Unit>?=null
 private var initialHistory=JsonArray(emptyList())
 private var historyReady:CompletableDeferred<Unit>?=null
 private val pendingHistory=mutableSetOf<String>()
 var started=false;private set
 var isMuted=false;private set
 suspend fun connect(instructions:String,history:JsonArray=JsonArray(emptyList()),language:String?=null)=withContext(Dispatchers.Main.immediate) {
  disconnect();isMuted=false;val epoch=attempt
  val config=configuration().validated();require(config.provider in listOf(ModelProvider.GLM,ModelProvider.GEMINI))
  selected=config;this@NativeProviderVoiceTransport.instructions=instructions;initialHistory=history
  require(instructions.toByteArray().size<=65536 && history.size<=40 && history.toString().toByteArray().size<=6000)
  val key=credential(config)?.let { ProviderConfiguration.validatedCredential(it) } ?: throw NativeVoiceException("Add this provider's API key in Settings.")
  val protocol=NativeVoiceProtocol(config.provider);state=protocol;began=SystemClock.elapsedRealtime();val ready=CompletableDeferred<Unit>();startup=ready
  val request=if(config.provider==ModelProvider.GLM) Request.Builder().url("https://open.bigmodel.cn/api/paas/v4/realtime").header("Authorization","Bearer "+NativeVoiceProtocol.glmToken(key,System.currentTimeMillis()/1000)).build()
   else {
    val token=try { geminiToken(key) } catch(e:Exception) { if(epoch==attempt) disconnect();throw e };ensureCurrent(epoch)
    Request.Builder().url("https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained").header("Authorization","Token $token").build()
   }
  socket=client.newWebSocket(request,object:WebSocketListener() {
   override fun onOpen(webSocket:WebSocket,response:Response) { scope.launch(Dispatchers.Main.immediate) { if(epoch==attempt) { socket=webSocket;try { send(setup(config.provider,instructions,history.isNotEmpty())) } catch(_:Exception) { fail(epoch,NativeVoiceException("Native voice setup could not be sent.")) } } else webSocket.cancel() } }
   override fun onMessage(webSocket:WebSocket,text:String) { scope.launch(Dispatchers.Main.immediate) { consume(epoch,text) } }
   override fun onMessage(webSocket:WebSocket,bytes:okio.ByteString) { if(bytes.size<=262144) onMessage(webSocket,bytes.utf8()) else fail(epoch,NativeVoiceException("Native voice returned an invalid response.")) }
   override fun onFailure(webSocket:WebSocket,t:Throwable,response:Response?) { fail(epoch,NativeVoiceException("Native voice could not connect.",response?.code in listOf(404,501))) }
   override fun onClosed(webSocket:WebSocket,code:Int,reason:String) { fail(epoch,NativeVoiceException("Native voice disconnected. Please reconnect.")) }
  })
  try {
   withTimeout(20000) { ready.await() };ensureCurrent(epoch)
   val historyFrames=NativeVoiceProtocol.historyCommands(config.provider,history)
   val historyAcknowledged=CompletableDeferred<Unit>();historyReady=historyAcknowledged
   pendingHistory.clear()
   if(config.provider==ModelProvider.GLM) historyFrames.forEach { frame -> (frame["item"] as? JsonObject)?.str("id")?.let(pendingHistory::add) }
   historyFrames.forEach(::send)
   if(pendingHistory.isEmpty()) historyAcknowledged.complete(Unit)
   withTimeout(20000) { historyAcknowledged.await() };ensureCurrent(epoch)
   audio.muted=isMuted
   audio.onPCM={ pcm -> scope.launch(Dispatchers.Main.immediate) {
    if(epoch==attempt && started && !isMuted && configuration()==config) {
     val data=Base64.getEncoder().encodeToString(if(config.provider==ModelProvider.GLM) NativeVoiceProtocol.wav(pcm) else pcm)
     val frame=if(config.provider==ModelProvider.GLM) buildJsonObject { put("type","input_audio_buffer.append");put("audio",data) } else buildJsonObject { put("realtimeInput",buildJsonObject { put("audio",buildJsonObject { put("mimeType","audio/pcm;rate=16000");put("data",data) }) }) }
     try { send(frame) } catch(_:Exception) { fail(epoch,NativeVoiceException("Native voice could not keep up. Please reconnect.")) }
    }
   } }
   audio.onLevels={ i,o -> scope.launch(Dispatchers.Main.immediate) { if(epoch==attempt) onLevels?.invoke(i,o) } }
   audio.onFailure={ fail(epoch,NativeVoiceException("Device voice audio stopped. Please reconnect.")) }
   audio.start();began=SystemClock.elapsedRealtime();started=true
   onCapability?.invoke(if(config.provider==ModelProvider.GLM) "GLM native realtime voice" else "Gemini native Live voice")
   onEvent?.invoke(NativeVoiceProtocol.json("session.started"))
  } catch(e:TimeoutCancellationException) { if(epoch==attempt) disconnect();throw NativeVoiceException("Native voice connection timed out. Please try again.") }
  catch(e:CancellationException) { if(epoch==attempt) disconnect();throw e }
  catch(e:Exception) { if(epoch==attempt) disconnect();throw if(e is NativeVoiceException) e else NativeVoiceException("Native voice could not start. Check model access and microphone permission.") }
 }
 private fun consume(epoch:Long,text:String) {
  if(epoch!=attempt) return
  try {
   check(configuration()==selected)
   if(selected?.provider==ModelProvider.GLM && text.toByteArray().size<=262144) {
    val event=Json.parseToJsonElement(text).jsonObject
    if(event.str("type")=="conversation.item.created") {
     (event["item"] as? JsonObject)?.str("id")?.let(pendingHistory::remove)
     if(pendingHistory.isEmpty()) historyReady?.complete(Unit)
    }
   }
   val update=state!!.consume(text,SystemClock.elapsedRealtime()-began)
   if(update.configured && startup?.isCompleted==false) startup?.complete(Unit)
   if(update.clearPlayback) audio.clearPlayback()
   if(started) {
    update.events.filter { it.str("type")!="session.started" }.forEach { onEvent?.invoke(it) }
    update.audio.filter { !isMuted }.forEach { if(!audio.enqueue(it)) throw NativeVoiceException("Voice playback could not keep up. Please reconnect.") }
   }
  } catch(e:Exception) { fail(epoch,if(e is NativeVoiceException) e else NativeVoiceException("Native voice returned an invalid response.")) }
 }
 private fun fail(epoch:Long,error:NativeVoiceException) { scope.launch(Dispatchers.Main.immediate) {
  if(epoch!=attempt) return@launch
  if(startup?.isCompleted==false) startup?.completeExceptionally(error)
  else { disconnect();onFailure?.invoke(error.message ?: "Native voice disconnected.") }
 } }
 private fun send(frame:JsonObject) {
  check(frame.toString().toByteArray().size<=262144)
  val ws=socket ?: throw NativeVoiceException("Native voice is disconnected.")
  if(ws.queueSize()>1048576 || !ws.send(frame.toString())) throw NativeVoiceException("Native voice could not keep up. Please reconnect.")
 }
 fun sendTypedText(text:String) { sendInstruction("The learner typed: "+text.take(2000),true) }
 fun sendInstruction(text:String,requestResponse:Boolean) {
  scope.launch(Dispatchers.Main.immediate) {
   if(!started) return@launch
   try {
    val cancelPrevious = requestResponse && state?.prepareResponse()==true
    if(selected?.provider==ModelProvider.GLM) {
     if(requestResponse) {
      if(cancelPrevious) send(NativeVoiceProtocol.json("response.cancel"))
      audio.clearPlayback()
     }
     send(buildJsonObject {
      put("type","conversation.item.create")
      put("item",buildJsonObject {
       put("type","message")
       put("role","system")
       put("content",buildJsonArray {
        add(buildJsonObject { put("type","input_text");put("text",text.take(8192)) })
       })
      })
     })
     if(requestResponse) send(NativeVoiceProtocol.json("response.create"))
    } else {
     if(!requestResponse) {
      onCapability?.invoke("Live learning-plan updates apply at your next conversation.")
      return@launch
     }
     audio.clearPlayback()
     send(buildJsonObject {
      put("clientContent",buildJsonObject {
       put("turns",buildJsonArray {
        add(buildJsonObject {
         put("role","user")
         put("parts",buildJsonArray { add(buildJsonObject { put("text",text.take(8192)) }) })
        })
       })
       put("turnComplete",true)
      })
     })
    }
    if(requestResponse) onEvent?.invoke(NativeVoiceProtocol.json("response.created"))
   } catch(_:Exception) {
    onFailure?.invoke("The voice update could not be sent. Please reconnect.")
   }
  }
 }
 fun setMuted(value:Boolean) { scope.launch(Dispatchers.Main.immediate) {
  if(isMuted==value) return@launch
  isMuted=value;audio.muted=value
  if(value) {
   // Invalidate the protocol turn as well as its queued PCM. Unmute must not
   // resume the tail of the response that the learner just stopped hearing.
   val activeOutput=state?.hasActiveOutput==true
   val cancelled=state?.setMuted(true)==true
   audio.clearPlayback()
   if(activeOutput && selected?.provider==ModelProvider.GLM) {
    try { send(NativeVoiceProtocol.json("response.cancel")) }
    catch(_:Exception) { onFailure?.invoke("The voice update could not be sent. Please reconnect.") }
   }
   if(cancelled) onEvent?.invoke(NativeVoiceProtocol.json("response.done"))
  } else state?.setMuted(false)
 } }
 fun close() { if(android.os.Looper.myLooper()==android.os.Looper.getMainLooper()) disconnect() else android.os.Handler(android.os.Looper.getMainLooper()).post { disconnect() } }
 private fun disconnect() { if(started) onEvent?.invoke(buildJsonObject { put("type","session.usage.updated");put("usage",buildJsonObject { put("seconds",maxOf(0L,SystemClock.elapsedRealtime()-began)/1000.0) }) });attempt++;started=false;historyReady?.cancel();historyReady=null;pendingHistory.clear();startup?.cancel();startup=null;socket?.cancel();socket=null;audio.close();state=null;selected=null }
 private fun ensureCurrent(epoch:Long) { if(epoch!=attempt || configuration()!=selected) throw CancellationException() }
 private suspend fun geminiToken(key:String):String {
  val now=Instant.now()
  val body=buildJsonObject { put("uses",1);put("newSessionExpireTime",now.plusSeconds(60).toString());put("expireTime",now.plusSeconds(3900).toString()) }
  val request=Request.Builder().url("https://generativelanguage.googleapis.com/v1beta/auth_tokens").header("x-goog-api-key",key).post(body.toString().toRequestBody("application/json".toMediaType())).build()
  return suspendCancellableCoroutine { continuation ->
   val call=client.newBuilder().callTimeout(20,TimeUnit.SECONDS).readTimeout(20,TimeUnit.SECONDS).build().newCall(request);continuation.invokeOnCancellation { call.cancel() }
   call.enqueue(object:Callback {
    override fun onFailure(call:Call,e:IOException) { if(continuation.isActive) continuation.resumeWithException(NativeVoiceException("Gemini voice authorization could not connect.")) }
    override fun onResponse(call:Call,response:Response) {
     try {
      val token=response.use { if(!it.isSuccessful) throw NativeVoiceException("Gemini native voice is unavailable for this account.",it.code in listOf(404,501))
       val body=it.body ?: throw NativeVoiceException("Gemini voice authorization was incomplete.")
       require(body.contentLength()<=262144)
       val source=body.source();val buffer=okio.Buffer();var total=0L
       while(true) { val n=source.read(buffer,minOf(8192L,262145-total));if(n==-1L) break;total+=n;require(total<=262144) }
       val bytes=buffer.readByteArray()
       require(bytes.size<=262144);val value=Json.parseToJsonElement(String(bytes)).jsonObject.str("name") ?: throw NativeVoiceException("Gemini voice authorization was incomplete.")
       require(value.length in 1..8192 && value.all { c -> c.code in 33..126 });value
      }
      if(continuation.isActive) continuation.resume(token)
     } catch(e:Exception) { if(continuation.isActive) continuation.resumeWithException(if(e is NativeVoiceException) e else NativeVoiceException("Gemini voice authorization was incomplete.")) }
    }
   })
  }
 }
 private fun setup(provider:ModelProvider,instructions:String,history:Boolean):JsonObject=if(provider==ModelProvider.GLM) buildJsonObject {
  put("type","session.update");put("session",buildJsonObject { put("modalities",buildJsonArray { add(JsonPrimitive("audio"));add(JsonPrimitive("text")) });put("input_audio_format","wav");put("output_audio_format","pcm");put("instructions",instructions);put("turn_detection",buildJsonObject { put("type","server_vad") });put("beta_fields",buildJsonObject { put("chat_mode","audio");put("tts_source","e2e");put("auto_search",false) });put("tools",JsonArray(emptyList())) })
 } else buildJsonObject { put("setup",buildJsonObject {
  put("model","models/gemini-3.8-live");put("generationConfig",buildJsonObject { put("responseModalities",buildJsonArray { add(JsonPrimitive("AUDIO")) }) });put("systemInstruction",buildJsonObject { put("parts",buildJsonArray { add(buildJsonObject { put("text",instructions) }) }) });put("inputAudioTranscription",buildJsonObject {});put("outputAudioTranscription",buildJsonObject {});put("sessionResumption",buildJsonObject {});put("realtimeInputConfig",buildJsonObject { put("automaticActivityDetection",buildJsonObject { put("disabled",false) });put("activityHandling","START_OF_ACTIVITY_INTERRUPTS") });put("contextWindowCompression",buildJsonObject { put("slidingWindow",buildJsonObject {}) });if(history) put("historyConfig",buildJsonObject { put("initialHistoryInClientContent",true) })
 }) }
}
