package cn.gd306.tideenglish.network
import cn.gd306.tideenglish.core.ModelProvider
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
class NativeVoiceProtocolTest {
 @Test fun glmSignsJWTAndFramesIndependentWavChunks() {
  val token=NativeVoiceProtocol.glmToken("identifier.secret",1000)
  val payload=String(java.util.Base64.getUrlDecoder().decode(token.split('.')[1]))
  assertEquals(1600,Json.parseToJsonElement(payload).jsonObject["exp"]!!.jsonPrimitive.int)
  val wav=NativeVoiceProtocol.wav(byteArrayOf(1,2,3,4)); assertEquals("RIFF",String(wav.copyOfRange(0,4))); assertEquals(48,wav.size)
  assertThrows(IllegalArgumentException::class.java) { NativeVoiceProtocol.wav(byteArrayOf(1)) }
 }
 @Test fun nativeAudioRejectsMalformedAndOversizedFrames() {
  val protocol=NativeVoiceProtocol(ModelProvider.GLM)
  assertThrows(IllegalArgumentException::class.java) { protocol.consume("""{"type":"response.audio.delta","delta":"AQ=="}""",10) }
  assertThrows(IllegalArgumentException::class.java) { protocol.consume(" ".repeat(262145),10) }
 }
 @Test fun finalTranscriptDoesNotDuplicateDeltas() {
  val protocol=NativeVoiceProtocol(ModelProvider.GLM)
  val first=protocol.consume("""{"type":"response.audio_transcript.delta","response_id":"r","delta":"Hello"}""",10)
  val final=protocol.consume("""{"type":"response.audio_transcript.done","response_id":"r","transcript":"Hello"}""",20)
  assertEquals("Hello",first.events.single()["delta"]!!.jsonPrimitive.content); assertTrue(final.events.isEmpty())
 }
 @Test fun geminiInterruptedAudioIsDiscardedUntilBoundary() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  protocol.consume("""{"serverContent":{"interrupted":true}}""",1)
  val result=protocol.consume("""{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}}]}}}""",2)
  assertTrue(result.audio.isEmpty())
 }
 @Test fun identicalLearnerPhraseInNewSpeechIsRetained() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  repeat(2) { turn ->
   protocol.consume("""{"voiceActivity":{"type":"ACTIVITY_START"}}""",turn*100L)
   val result=protocol.consume("""{"serverContent":{"inputTranscription":{"text":"yes","finished":true}}}""",turn*100L+20)
   assertEquals("yes",result.events.single()["delta"]!!.jsonPrimitive.content)
  }
 }
 @Test fun cumulativeOffsetTranscriptionAppendsOnlySuffix() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  protocol.consume("""{"serverContent":{"inputTranscription":{"text":"Good","startOffset":"1s"}}}""",1100)
  val result=protocol.consume("""{"serverContent":{"inputTranscription":{"text":"Good morning","startOffset":"1s"}}}""",1200)
  assertEquals(" morning",result.events.single()["delta"]!!.jsonPrimitive.content)
 }
 @Test fun geminiPublishesOneWorkingBoundaryPerOutputTurn() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  val first=protocol.consume("""{"serverContent":{"outputTranscription":{"text":"Hello"}}}""",10)
  val second=protocol.consume("""{"serverContent":{"outputTranscription":{"text":" there"}}}""",20)
  assertEquals(1,first.events.count { it["type"]==JsonPrimitive("response.created") })
  assertEquals(0,second.events.count { it["type"]==JsonPrimitive("response.created") })
  val done=protocol.consume("""{"serverContent":{"turnComplete":true}}""",30)
  assertTrue(done.events.any { it["type"]==JsonPrimitive("response.done") })
 }
 @Test fun glmDropsAudioAfterCompletedOrCancelledResponse() {
  val protocol=NativeVoiceProtocol(ModelProvider.GLM)
  protocol.consume("""{"type":"response.created","response":{"id":"one"}}""",0)
  protocol.consume("""{"type":"response.done","response":{"id":"one","status":"completed"}}""",1)
  assertTrue(protocol.consume("""{"type":"response.audio.delta","response_id":"one","delta":"AQI="}""",2).audio.isEmpty())
  protocol.consume("""{"type":"response.created","response":{"id":"two"}}""",3)
  protocol.cancelOutput()
  assertTrue(protocol.consume("""{"type":"response.audio.delta","response_id":"two","delta":"AQI="}""",4).audio.isEmpty())
 }
 @Test fun glmHistoryUsesNativeContentTypesAndUniqueAcknowledgementIDs() {
  val history=Json.parseToJsonElement("""[{"role":"user","content":[{"type":"input_text","text":"Hello"}]},{"role":"assistant","content":[{"type":"output_text","text":"Hi"}]}]""").jsonArray
  val frames=NativeVoiceProtocol.historyCommands(ModelProvider.GLM,history)
  assertEquals("input_text",frames[0]["item"]!!.jsonObject["content"]!!.jsonArray[0].jsonObject["type"]!!.jsonPrimitive.content)
  assertEquals("text",frames[1]["item"]!!.jsonObject["content"]!!.jsonArray[0].jsonObject["type"]!!.jsonPrimitive.content)
  assertNotEquals(frames[0]["item"]!!.jsonObject["id"],frames[1]["item"]!!.jsonObject["id"])
 }
 @Test fun cancelledGeminiTurnCannotResumeItsTranscriptOrAudioAfterUnmute() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  protocol.consume("""{"serverContent":{"outputTranscription":{"text":"Hello"}}}""",1)
  protocol.cancelOutput()
  val stale=protocol.consume("""{"serverContent":{"outputTranscription":{"text":" stale"},"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}}]}}}""",2)
  assertTrue(stale.audio.isEmpty())
  assertTrue(stale.events.isEmpty())
  protocol.consume("""{"serverContent":{"turnComplete":true}}""",3)
  val fresh=protocol.consume("""{"serverContent":{"outputTranscription":{"text":"New reply"}}}""",4)
  assertTrue(fresh.events.any { it["delta"]==JsonPrimitive("New reply") })
 }
 @Test fun cancelledGlmTurnCannotResumeItsTranscriptAfterUnmute() {
  val protocol=NativeVoiceProtocol(ModelProvider.GLM)
  protocol.consume("""{"type":"response.created","response":{"id":"before-mute"}}""",0)
  protocol.cancelOutput()
  val stale=protocol.consume("""{"type":"response.audio_transcript.delta","response_id":"before-mute","delta":"stale"}""",1)
  assertTrue(stale.events.isEmpty())
  val fresh=protocol.consume("""{"type":"response.audio_transcript.delta","response_id":"after-mute","delta":"fresh"}""",2)
  assertEquals("fresh",fresh.events.single()["delta"]!!.jsonPrimitive.content)
 }
 @Test fun muteBeforeFirstGeminiOutputInvalidatesThePendingTurnThroughCompletion() {
  val protocol=NativeVoiceProtocol(ModelProvider.GEMINI)
  protocol.consume("""{"setupComplete":{}}""",0)
  protocol.requestOutput()
  protocol.setMuted(true)
  val muted=protocol.consume("""{"serverContent":{"outputTranscription":{"text":"Old reply"}}}""",1)
  protocol.setMuted(false)
  val stale=protocol.consume("""{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}}]}}}""",2)
  assertTrue(muted.events.isEmpty());assertTrue(stale.audio.isEmpty())
  protocol.consume("""{"serverContent":{"turnComplete":true}}""",3)
  assertTrue(protocol.consume("""{"serverContent":{"outputTranscription":{"text":"Fresh"}}}""",4).events.any { it["delta"]==JsonPrimitive("Fresh") })
 }
 @Test fun muteBeforeGlmResponseCreatedAlsoRejectsLateReplyAfterUnmute() {
  val protocol=NativeVoiceProtocol(ModelProvider.GLM)
  protocol.requestOutput();protocol.setMuted(true);protocol.setMuted(false)
  protocol.consume("""{"type":"response.created","response":{"id":"old"}}""",1)
  assertTrue(protocol.consume("""{"type":"response.audio_transcript.delta","response_id":"old","delta":"old"}""",2).events.isEmpty())
  assertTrue(protocol.consume("""{"type":"response.audio.delta","response_id":"old","delta":"AQI="}""",3).audio.isEmpty())
  protocol.consume("""{"type":"response.done","response":{"id":"old"}}""",4)
  assertEquals("new",protocol.consume("""{"type":"response.audio_transcript.delta","response_id":"new","delta":"new"}""",5).events.single()["delta"]!!.jsonPrimitive.content)
 }
 @Test fun preparingTheFirstExplicitResponseNeverCancelsTheNewRequest() {
  for(provider in listOf(ModelProvider.GLM,ModelProvider.GEMINI)) {
   val protocol=NativeVoiceProtocol(provider)
   if(provider==ModelProvider.GEMINI) protocol.consume("""{"setupComplete":{}}""",0)
   assertFalse(protocol.prepareResponse())
   val output=if(provider==ModelProvider.GEMINI) """{"serverContent":{"outputTranscription":{"text":"Greeting"}}}"""
    else """{"type":"response.audio_transcript.delta","response_id":"first","delta":"Greeting"}"""
   assertTrue(protocol.consume(output,1).events.any { it["delta"]==JsonPrimitive("Greeting") })
  }
 }
}
