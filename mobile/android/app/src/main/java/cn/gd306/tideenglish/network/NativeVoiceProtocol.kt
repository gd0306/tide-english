package cn.gd306.tideenglish.network
import cn.gd306.tideenglish.core.ModelProvider
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.*

/** Bounded native voice framing. Payloads and authentication are never part of diagnostics. */
class NativeVoiceProtocol(private val provider:ModelProvider) {
 data class Update(val events:List<JsonObject> = emptyList(),val audio:List<ByteArray> = emptyList(),val clearPlayback:Boolean=false,val complete:Boolean=false,val configured:Boolean=false)
 private val transcripts=linkedMapOf<String,String>()
 private val finals=linkedSetOf<String>()
 private val cancelled=linkedSetOf<String>()
 private val activeResponses=linkedSetOf<String>()
 private val finishedResponses=linkedSetOf<String>()
 private var lastInputFinal:String?=null
 private var interrupted=false
 private var replyActive=false
 private var pendingOutput=false
 private var muted=false
 private var discardPendingGlm=false
 val hasActiveOutput get() = if(provider==ModelProvider.GLM) activeResponses.isNotEmpty() else replyActive
 fun requestOutput() { pendingOutput=true }
 fun prepareResponse():Boolean {
  val cancelActive = hasActiveOutput
  cancelOutput()
  requestOutput()
  return cancelActive
 }
 fun setMuted(value:Boolean):Boolean {
  if(muted==value) return false
  muted=value
  return value && cancelOutput()
 }
 private var inputTurn=0
 private var outputTurn=0
 private var sequence=0L
 private var inputStart=0L
 private var outputStart=0L
 var configured=false; private set
 fun consume(text:String,elapsed:Long):Update {
  require(text.toByteArray().size<=262144 && elapsed>=0)
  val event=Json.parseToJsonElement(text).jsonObject
  if(event["error"]!=null) throw NativeVoiceException("Native voice is unavailable for this account.",capability=capability(event["error"] as? JsonObject))
  val events=mutableListOf<JsonObject>(); val audio=mutableListOf<ByteArray>(); var clear=false; var complete=false
  if(provider==ModelProvider.GLM) {
   val type=event.str("type") ?: throw IllegalArgumentException("Invalid voice response.")
   val id=event.str("response_id") ?: "input"
   when(type) {
    "session.updated" -> { val session=event["session"] as? JsonObject
     if(session?.str("input_audio_format")=="wav" && session.str("output_audio_format")=="pcm" && (session["turn_detection"] as? JsonObject)?.str("type")=="server_vad" && (session["beta_fields"] as? JsonObject)?.str("chat_mode")=="audio" && (session["beta_fields"] as? JsonObject)?.get("auto_search")==JsonPrimitive(false)) { configured=true; events+=started() }
    }
    "input_audio_buffer.speech_started" -> { clear=true; inputStart=elapsed; outputTurn++;pendingOutput=true; cancelled.addAll(activeResponses);activeResponses.clear();require(cancelled.size<=2048) }
    "conversation.item.input_audio_transcription.completed" -> if(!muted) { pendingOutput=true;append(events,"input:"+(event.str("item_id") ?: inputTurn++),event.str("transcript") ?: "",true,false,inputStart,elapsed) }
    "response.audio.delta" -> if(muted || discardPendingGlm) { cancelled+="output:$id" } else if("output:$id" !in cancelled && id !in finishedResponses) { activeResponses+="output:$id";require(activeResponses.size<=128);audio+=decodeAudio(event.str("delta")) }
    "response.audio_transcript.delta", "response.audio_transcript.done" -> if(muted || discardPendingGlm) { cancelled+="output:$id" } else if("output:$id" !in cancelled) append(events,"output:$id",event.str(if(type.endsWith("done")) "transcript" else "delta") ?: "",type.endsWith("done"),true,outputStart,elapsed)
    "response.created" -> {
     (event["response"] as? JsonObject)?.str("id")?.let { if(muted || discardPendingGlm) cancelled+="output:$it" else activeResponses+="output:$it";require(activeResponses.size<=128 && cancelled.size<=2048) }
     outputStart=elapsed;pendingOutput=true
     if(!muted && !discardPendingGlm) events+=json("response.created")
    }
    "response.done" -> { (event["response"] as? JsonObject)?.str("id")?.let { activeResponses.remove("output:$it");finishedResponses+=it;require(finishedResponses.size<=1024) };complete=true;pendingOutput=false;discardPendingGlm=false; events+=json("response.done") }
   }
  } else {
   if(event["goAway"]!=null) throw NativeVoiceException("This native voice session is ending. Reconnect to continue.")
   if(event["setupComplete"] is JsonObject) { configured=true; events+=started() }
   val activity=event["voiceActivity"] as? JsonObject
   if(activity?.str("type")=="ACTIVITY_START") { inputTurn++;inputStart=elapsed;lastInputFinal=null;pendingOutput=true }
   val content=event["serverContent"] as? JsonObject
   if(content!=null) {
    require(configured)
    if(content["interrupted"]?.jsonPrimitive?.booleanOrNull==true) { interrupted=true; clear=true }
    (content["inputTranscription"] as? JsonObject)?.takeIf { !muted }?.let { value ->
     val text=value.str("text") ?: "";val final=value["finished"]?.jsonPrimitive?.booleanOrNull==true
     if(text.isNotEmpty()) pendingOutput=true
     if(!final || text.isNotEmpty() && text!=lastInputFinal) {
      val offset=value.str("startOffset")?.let { offsetMS(it) }
      append(events,if(offset!=null) "input:offset:$offset" else "input:$inputTurn",text,final,false,offset ?: inputStart,elapsed,cumulative=offset!=null)
      if(final) { lastInputFinal=text;inputTurn++;inputStart=elapsed }
     }
    }
    if(muted && (content["modelTurn"]!=null || content["outputTranscription"]!=null)) interrupted=true
    if(!interrupted) {
     if(!replyActive && (content["modelTurn"]!=null || content["outputTranscription"]!=null)) { replyActive=true;events+=json("response.created") }
     (content["outputTranscription"] as? JsonObject)?.let { value -> val offset=value.str("startOffset")?.let { offsetMS(it) };append(events,if(offset!=null) "output:$outputTurn:offset:$offset" else "output:$outputTurn",value.str("text") ?: "",value["finished"]?.jsonPrimitive?.booleanOrNull==true,true,outputStart+(offset ?: 0),elapsed,cumulative=offset!=null) }
     val parts=(content["modelTurn"] as? JsonObject)?.get("parts") as? JsonArray
     require(parts==null || parts.size<=64)
     parts?.forEach { part -> (part.jsonObject["inlineData"] as? JsonObject)?.let { blob -> require(blob.str("mimeType")=="audio/pcm;rate=24000"); audio+=decodeAudio(blob.str("data")) } }
     require(audio.sumOf { it.size }<=96000)
    }
    if(content["turnComplete"]?.jsonPrimitive?.booleanOrNull==true) { complete=true; interrupted=false;replyActive=false;pendingOutput=false; outputTurn++; outputStart=elapsed; events+=json("response.done") }
   }
  }
  require(cancelled.size<=2048)
  return Update(events,audio,clear,complete,configured)
 }
 fun cancelOutput(): Boolean {
  val active = pendingOutput || hasActiveOutput
  if(provider==ModelProvider.GLM) { if(pendingOutput && activeResponses.isEmpty()) discardPendingGlm=true;cancelled.addAll(activeResponses);activeResponses.clear();require(cancelled.size<=2048) }
  else if(active) interrupted=true
  return active
 }
 private fun append(events:MutableList<JsonObject>,key:String,value:String,final:Boolean,output:Boolean,start:Long,end:Long,cumulative:Boolean=false) {
  require(value.toByteArray().size<=32768 && (transcripts.size<2048 || transcripts.containsKey(key)))
  if(key in finals) return
  val previous=transcripts[key].orEmpty()
  val delta=if((final || cumulative) && value.startsWith(previous)) value.drop(previous.length) else if((final || cumulative) && previous.isNotEmpty()) "" else value
  val text=previous+delta; require(text.toByteArray().size<=32768); transcripts[key]=text
  if(final) finals+=key
  if(delta.isNotEmpty()) events+=buildJsonObject { put("type","session.${if(output) "output" else "input"}_transcript.delta");put("delta",delta);put("start_ms",start);put("end_ms",maxOf(start+1,end));put("event_id","native:$key:${sequence++}") }
 }
 private fun offsetMS(value:String):Long { require(value.endsWith("s") && value.length<32);val seconds=value.dropLast(1).toDouble();require(seconds.isFinite() && seconds>=0 && seconds<=2147483.647);return (seconds*1000).toLong() }
 private fun decodeAudio(value:String?):ByteArray { require(value!=null && value.length<=128000); val pcm=Base64.getDecoder().decode(value); require(pcm.isNotEmpty() && pcm.size%2==0 && pcm.size<=96000); return pcm }
 private fun capability(error:JsonObject?):Boolean { val code=error?.get("code")?.jsonPrimitive?.contentOrNull; return if(provider==ModelProvider.GLM) code in listOf("1212","1220","1311") else code in listOf("404","501") }
 private fun started()=json("session.started")
 companion object {
  fun json(type:String)=buildJsonObject { put("type",type) }
  fun historyCommands(provider:ModelProvider,history:JsonArray):List<JsonObject> {
   require(history.size<=40 && history.toString().toByteArray().size<=6000)
   if(history.isEmpty()) return emptyList()
   fun parts(item:JsonObject,role:String)=buildJsonArray {
    val content=item["content"] as? JsonArray ?: throw IllegalArgumentException("Invalid voice history.")
    require(content.isNotEmpty())
    content.forEach { element ->
     val text=element.jsonObject.str("text") ?: throw IllegalArgumentException("Invalid voice history.")
     require(text.isNotBlank())
     add(buildJsonObject {
      if(provider==ModelProvider.GLM) put("type",if(role=="assistant") "text" else "input_text")
      put("text",if(provider==ModelProvider.GEMINI && role=="system") "Conversation context: $text" else text)
     })
    }
   }
   return if(provider==ModelProvider.GLM) history.map { element ->
    val item=element.jsonObject;val role=item.str("role") ?: "";require(role in listOf("user","assistant","system"))
    buildJsonObject { put("type","conversation.item.create");put("item",buildJsonObject { put("id","history-"+java.util.UUID.randomUUID());put("type","message");put("role",role);put("content",parts(item,role)) }) }
   } else listOf(buildJsonObject { put("clientContent",buildJsonObject { put("turns",buildJsonArray {
    history.forEach { element -> val item=element.jsonObject;val role=item.str("role") ?: "";require(role in listOf("user","assistant","system"));add(buildJsonObject { put("role",if(role=="assistant") "model" else "user");put("parts",parts(item,role)) }) }
   });put("turnComplete",true) }) })
  }
  fun glmToken(key:String,now:Long):String {
   require(key.length<=4096 && key.all { it.code in 33..126 } && now in 0..8999999999999)
   val pieces=key.split('.'); require(pieces.size==2 && pieces.all { it.isNotEmpty() })
   fun encoded(data:ByteArray)=Base64.getUrlEncoder().withoutPadding().encodeToString(data)
   val header="{\"alg\":\"HS256\",\"sign_type\":\"SIGN\"}"
   val payload=buildJsonObject { put("api_key",pieces[0]); put("exp",now+600);put("timestamp",now*1000) }.toString()
   val input=encoded(header.toByteArray())+"."+encoded(payload.toByteArray())
   val mac=Mac.getInstance("HmacSHA256");mac.init(SecretKeySpec(pieces[1].toByteArray(),"HmacSHA256"))
   return input+"."+encoded(mac.doFinal(input.toByteArray()))
  }
  fun wav(pcm:ByteArray):ByteArray { require(pcm.isNotEmpty() && pcm.size%2==0 && pcm.size<=32000)
   return ByteBuffer.allocate(pcm.size+44).order(ByteOrder.LITTLE_ENDIAN).put("RIFF".toByteArray()).putInt(pcm.size+36).put("WAVEfmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(16000).putInt(32000).putShort(2).putShort(16).put("data".toByteArray()).putInt(pcm.size).put(pcm).array()
  }
 }
}
internal fun JsonObject.str(key:String)=(this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
class NativeVoiceException(message:String,val capability:Boolean=false):java.io.IOException(message)
