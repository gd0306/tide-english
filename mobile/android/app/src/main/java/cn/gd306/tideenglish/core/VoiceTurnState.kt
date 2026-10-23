package cn.gd306.tideenglish.core
/** Main-thread state machine: late recognition cannot become a second turn or hear playback. */
class VoiceTurnState {
 private var generation=0L
 private var active=false
 private var pending=""
 private var muted=false
 private var outputActive=false
 private var requestActive=false
 val canListen get()=!muted && !outputActive && !requestActive
 fun begin():Long { generation++; active=canListen; pending=""; return generation }
 fun update(text:String,generation:Long):Boolean {
  if(!active || generation!=this.generation) return false
  val value=text.trim().take(2000); if(value==pending) return false; pending=value; return true
 }
 fun commit(generation:Long):String? { if(!active || generation!=this.generation) return null; active=false; val text=pending; pending=""; return text.takeIf { it.isNotEmpty() } }
 fun cancel() { generation++; active=false; pending="" }
 fun setMuted(value:Boolean) { if(value!=muted) { muted=value; cancel() } }
 fun setOutputActive(value:Boolean) { if(value!=outputActive) { outputActive=value; cancel() } }
 fun setRequestActive(value:Boolean) { if(value!=requestActive) { requestActive=value; cancel() } }
}
