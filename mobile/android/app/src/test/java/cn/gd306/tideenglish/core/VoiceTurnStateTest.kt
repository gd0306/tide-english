package cn.gd306.tideenglish.core
import org.junit.Assert.*
import org.junit.Test
class VoiceTurnStateTest {
 @Test fun onlyOneFinalTranscriptAndNoEmptyRequest() {
  val state=VoiceTurnState(); val generation=state.begin(); assertNull(state.commit(generation))
  val next=state.begin(); assertTrue(state.update("hello",next)); assertEquals("hello",state.commit(next)); assertNull(state.commit(next))
 }
 @Test fun outputMuteAndRequestsInvalidateStaleRecognition() {
  val state=VoiceTurnState(); val generation=state.begin(); state.update("stale",generation)
  state.setOutputActive(true); assertFalse(state.canListen); assertNull(state.commit(generation)); state.setOutputActive(false)
  state.setRequestActive(true); assertFalse(state.canListen); state.setRequestActive(false)
  state.setMuted(true); assertFalse(state.canListen); state.setMuted(false); assertTrue(state.canListen)
 }
}
