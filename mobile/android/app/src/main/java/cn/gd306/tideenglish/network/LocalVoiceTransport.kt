package cn.gd306.tideenglish.network

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import cn.gd306.tideenglish.core.VoiceTurnState
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.serialization.json.*

/** On-device recognition, selected-provider text generation, and device speech. Never changes supplier. */
class LocalVoiceTransport(context:Context,private val scope:CoroutineScope,private val teachingClient:TeachingClient) {
 var onEvent:((JsonObject)->Unit)?=null
 var onFailure:((String)->Unit)?=null
 var onLevels:((Double,Double)->Unit)?=null
 var onCapability:((String)->Unit)?=null
 var onUsage:((APIUsage)->Unit)?=null
 private var beganAt=0L
 private val context=context.applicationContext
 private val turns=VoiceTurnState()
 private var recognizer:SpeechRecognizer?=null
 private var tts:TextToSpeech?=null
 private var ttsReady=false
 private var generation=0L
 private var recognitionEpoch=0L
 private var playbackID:String?=null
 private var requestJob:Job?=null
 private var instructions=""
 private var appendedInstructions=""
 private var language="en-US"
 private var history=JsonArray(emptyList()).toString()
 private var clock=0L
 private var recognizerAvailable=false
 var started=false; private set
 var isMuted=false; private set
 suspend fun connect(instructions:String,history:JsonArray=JsonArray(emptyList()),language:String?=null)=withContext(Dispatchers.Main.immediate) {
  dispose(); beganAt=android.os.SystemClock.elapsedRealtime();clock=0; isMuted=false; turns.setMuted(false); started=true; this@LocalVoiceTransport.instructions=instructions;appendedInstructions=""
  this@LocalVoiceTransport.history=history.toString(); this@LocalVoiceTransport.language=language ?: "en-US"
  val current=generation
  emit("session.started")
  onCapability?.invoke("Device speech with the selected provider. Voice requires on-device recognition; typing is always available.")
  tts=TextToSpeech(context) { status -> scope.launch(Dispatchers.Main.immediate) {
   if(!started || generation!=current) return@launch
   ttsReady=status==TextToSpeech.SUCCESS
   if(ttsReady) {
    val locale=Locale.forLanguageTag(this@LocalVoiceTransport.language)
    val result=tts?.setLanguage(locale)
    val voices=tts?.voices.orEmpty().filter { !it.isNetworkConnectionRequired && it.locale.language==locale.language }
    val voice=voices.firstOrNull { it.locale.country==locale.country } ?: voices.firstOrNull()
    ttsReady=result!=TextToSpeech.LANG_MISSING_DATA && result!=TextToSpeech.LANG_NOT_SUPPORTED && voice!=null && tts?.setVoice(voice)==TextToSpeech.SUCCESS
   }
   if(!ttsReady) onCapability?.invoke("Device speech output is unavailable for this language. Replies remain visible as text.")
  } }
  tts?.setOnUtteranceProgressListener(object:UtteranceProgressListener() {
   override fun onStart(id:String?) { }
   override fun onRangeStart(id:String?,start:Int,end:Int,frame:Int) { scope.launch(Dispatchers.Main.immediate) { if(started && id==playbackID) onLevels?.invoke(0.0,0.25) } }
   override fun onDone(id:String?)=completePlayback(id)
   @Deprecated("Android callback") override fun onError(id:String?) { scope.launch(Dispatchers.Main.immediate) { if(id==playbackID) onCapability?.invoke("Device speech output is unavailable for this language. Replies remain visible as text.") };completePlayback(id) }
  })
  recognizerAvailable=Build.VERSION.SDK_INT>=31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
  if(recognizerAvailable) startListening() else onCapability?.invoke("On-device speech recognition is unavailable on this device. Use typing to continue with this provider.")
 }
 private fun startListening() {
  if(!started || !recognizerAvailable || !turns.canListen) return
  recognizer?.destroy()
  if(Build.VERSION.SDK_INT<31) return
  val turn=turns.begin(); val current=generation; val recognition=++recognitionEpoch
  recognizer=SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
   setRecognitionListener(object:RecognitionListener {
    override fun onReadyForSpeech(params:Bundle?) { }
    override fun onBeginningOfSpeech() { if(current==generation && recognition==recognitionEpoch) onLevels?.invoke(0.15,0.0) }
    override fun onRmsChanged(rmsdB:Float) { if(current==generation && recognition==recognitionEpoch) onLevels?.invoke((rmsdB/12.0).coerceIn(0.0,1.0),0.0) }
    override fun onBufferReceived(buffer:ByteArray?) { }
    override fun onEndOfSpeech() { if(current==generation && recognition==recognitionEpoch) onLevels?.invoke(0.0,0.0) }
    override fun onPartialResults(results:Bundle?) { if(current==generation && recognition==recognitionEpoch) turns.update(results.text(),turn) }
    override fun onResults(results:Bundle?) {
     if(current!=generation || recognition!=recognitionEpoch || !started) return
     turns.update(results.text(),turn)
     val text=turns.commit(turn)
     if(text!=null) request(text) else restartSoon(current)
    }
    override fun onError(error:Int) {
     if(current!=generation || recognition!=recognitionEpoch || !started) return
     turns.cancel(); onLevels?.invoke(0.0,0.0)
     if(error==SpeechRecognizer.ERROR_NO_MATCH || error==SpeechRecognizer.ERROR_SPEECH_TIMEOUT) restartSoon(current)
     else { recognizerAvailable=false; onCapability?.invoke("On-device recognition could not start. Use typing to continue with this provider.") }
    }
    override fun onEvent(eventType:Int,params:Bundle?) { }
   })
   try { startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM).putExtra(RecognizerIntent.EXTRA_LANGUAGE,language).putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true).putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true)) }
   catch (_:Exception) { recognizerAvailable=false; turns.cancel(); onCapability?.invoke("On-device recognition is unavailable. Use typing to continue with this provider.") }
  }
 }
 private fun Bundle?.text()=this?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
 private fun restartSoon(current:Long) { scope.launch(Dispatchers.Main.immediate) { delay(400); if(current==generation) startListening() } }
 fun sendTypedText(text:String) { scope.launch(Dispatchers.Main.immediate) { if(started && text.isNotBlank()) { clock+=3;request(text.trim().take(2000),persistUser=false,appendUser=true) } } }
 fun sendInstruction(text:String,requestResponse:Boolean) { scope.launch(Dispatchers.Main.immediate) {
  if(!started) return@launch
  appendedInstructions=(appendedInstructions+"\n"+text.take(5000)).takeLast(5000)
  if(requestResponse) request("Please continue the conversation using the latest instructions.",false)
 } }
 private fun request(text:String,persistUser:Boolean=true,appendUser:Boolean=persistUser) {
  if(!started || requestJob?.isActive==true) return
  recognitionEpoch++;recognizer?.cancel();playbackID=null;tts?.stop();turns.setOutputActive(false); turns.setRequestActive(true)
  val current=generation
  if(persistUser) transcript("input",text)
  if(appendUser) history=(history+"\nLearner: "+text).takeLast(24000)
  emit("response.created")
  requestJob=scope.launch(Dispatchers.Main.immediate) {
   try {
    val result=teachingClient.respond(instructions+"\n"+appendedInstructions,history, purpose=HelperPurpose.TYPED_REPLY)
    if(current!=generation || !started) return@launch
    onUsage?.invoke(result.usage)
    transcript("output",result.text); history=(history+"\nTutor: "+result.text).takeLast(24000)
    turns.setRequestActive(false)
    if(ttsReady && !isMuted) {
     turns.setOutputActive(true); onLevels?.invoke(0.0,0.25)
     val utterance=UUID.randomUUID().toString();playbackID=utterance
     val success=tts?.speak(result.text,TextToSpeech.QUEUE_FLUSH,null,utterance)==TextToSpeech.SUCCESS
     if(!success) { playbackID=null;turns.setOutputActive(false);onCapability?.invoke("Device speech output is unavailable for this language. Replies remain visible as text."); restartSoon(current) }
    } else restartSoon(current)
   } catch(e:CancellationException) { throw e }
   catch (_:Exception) { if(current==generation) onFailure?.invoke("The selected provider could not complete this voice turn. Please try again.") }
   finally { if(current==generation) { turns.setRequestActive(false); emit("response.done") } }
  }
 }
 private fun completePlayback(id:String?) { scope.launch(Dispatchers.Main.immediate) { if(started && id!=null && id==playbackID) { playbackID=null; turns.setOutputActive(false); onLevels?.invoke(0.0,0.0); startListening() } } }
 fun setMuted(value:Boolean) { scope.launch(Dispatchers.Main.immediate) {
  if(isMuted==value) return@launch
  isMuted=value; recognitionEpoch++;turns.setMuted(value); recognizer?.cancel()
  if(value) { generation++; playbackID=null;requestJob?.cancel(); tts?.stop(); turns.setOutputActive(false); turns.setRequestActive(false); onLevels?.invoke(0.0,0.0);emit("response.done") }
  else startListening()
 } }
 fun close() { if(android.os.Looper.myLooper()==android.os.Looper.getMainLooper()) dispose() else android.os.Handler(android.os.Looper.getMainLooper()).post { dispose() } }
 private fun dispose() {
  if(started) onEvent?.invoke(buildJsonObject { put("type","session.usage.updated");put("usage",buildJsonObject { put("seconds",maxOf(0L,android.os.SystemClock.elapsedRealtime()-beganAt)/1000.0) }) })
  generation++;recognitionEpoch++;playbackID=null; started=false; requestJob?.cancel(); requestJob=null; turns.cancel(); turns.setRequestActive(false); turns.setOutputActive(false)
  recognizer?.destroy(); recognizer=null; tts?.stop(); tts?.shutdown(); tts=null; ttsReady=false; onLevels?.invoke(0.0,0.0)
 }
 private fun transcript(kind:String,text:String) {
  val start=clock; clock+=maxOf(1,text.length*50).toLong()
  onEvent?.invoke(buildJsonObject { put("type","session.${kind}_transcript.delta"); put("delta",text); put("start_ms",start); put("end_ms",clock); put("event_id",UUID.randomUUID().toString()) })
 }
 private fun emit(type:String) { onEvent?.invoke(buildJsonObject { put("type",type) }) }
}
