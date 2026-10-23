package cn.gd306.tideenglish.network

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*

/** PCM16 mono capture at 16kHz and bounded ordered playback at 24kHz. */
internal class NativeRealtimeAudio(private val context:Context,private val scope:CoroutineScope) {
 var onPCM:((ByteArray)->Unit)?=null
 var onLevels:((Double,Double)->Unit)?=null
 var onFailure:(()->Unit)?=null
 private var running=AtomicBoolean(false)
 private val captureLock=Any()
 private var recorder:AudioRecord?=null
 private var echo:android.media.audiofx.AcousticEchoCanceler?=null
 private val manager=context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
 private var priorMode:Int?=null
 private var focus:AudioFocusRequest?=null
 private var ownsRoute=false
 private var legacyRoute:LegacyCommunicationAudioRoute?=null
 private var devices:AudioDeviceCallback?=null
 private var lifecycle=0L
 private var player:AudioTrack?=null
 private var capture:Job?=null
 private var playback:Job?=null
 private val queue=ArrayBlockingQueue<ByteArray>(32)
 private val queuedBytes=java.util.concurrent.atomic.AtomicInteger(0)
 @Volatile var muted=false
 private val playbackLock=Any()
 @Volatile private var outputGeneration=0L
 fun start() {
  close();val epoch=lifecycle
  check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED) { "Microphone permission is required." }
  val minimum=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)
  check(minimum>0)
  val input=AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION,16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,maxOf(minimum,6400))
  val output=try { AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()).setAudioFormat(AudioFormat.Builder().setSampleRate(24000).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()).setBufferSizeInBytes(maxOf(9600,AudioTrack.getMinBufferSize(24000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT))).setTransferMode(AudioTrack.MODE_STREAM).build() } catch(e:Exception) { input.release();throw e }
  if(input.state!=AudioRecord.STATE_INITIALIZED || output.state!=AudioTrack.STATE_INITIALIZED) { input.release();output.release();throw IllegalStateException("Device audio could not start.") }
  recorder=input;player=output
  if(android.media.audiofx.AcousticEchoCanceler.isAvailable()) echo=runCatching { android.media.audiofx.AcousticEchoCanceler.create(input.audioSessionId)?.apply { enabled=true } }.getOrNull()
  try {
   val focusRequest=AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
    .setAcceptsDelayedFocusGain(false).setOnAudioFocusChangeListener({ change -> if(epoch==lifecycle && (change==AudioManager.AUDIOFOCUS_LOSS || change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)) onFailure?.invoke() },android.os.Handler(android.os.Looper.getMainLooper())).build()
   check(manager.requestAudioFocus(focusRequest)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "Voice audio focus is unavailable." }
   focus=focusRequest;priorMode=manager.mode;manager.mode=AudioManager.MODE_IN_COMMUNICATION
   if(android.os.Build.VERSION.SDK_INT<31) legacyRoute=LegacyCommunicationAudioRoute(context,manager,scope,manager.isSpeakerphoneOn,onFailure={ onFailure?.invoke() }).also { it.start() }
   routeAudio()
   devices=object:AudioDeviceCallback() {
    override fun onAudioDevicesAdded(addedDevices:Array<out AudioDeviceInfo>) { if(epoch==lifecycle) runCatching { routeAudio() }.onFailure { onFailure?.invoke() } }
    override fun onAudioDevicesRemoved(removedDevices:Array<out AudioDeviceInfo>) { if(epoch==lifecycle) runCatching { routeAudio() }.onFailure { onFailure?.invoke() } }
   }.also { manager.registerAudioDeviceCallback(it,android.os.Handler(android.os.Looper.getMainLooper())) }
  } catch(e:Exception) { close();throw e }
  val run=AtomicBoolean(true);running=run
  try { input.startRecording();output.play() } catch(e:Exception) { close();throw e }
  capture=scope.launch(Dispatchers.IO) {
   val buffer=ByteArray(3200)
   while(run.get() && isActive) {
    val count=runCatching { synchronized(captureLock) { if(run.get()) input.read(buffer,0,buffer.size) else -1 } }.getOrDefault(-1)
    if(count<0) { if(run.get()) onFailure?.invoke();break }
    if(count>0 && run.get() && !muted && count%2==0) { val pcm=buffer.copyOf(count);onPCM?.invoke(pcm);onLevels?.invoke(level(pcm),0.0) }
   }
  }
  playback=scope.launch(Dispatchers.IO) {
   while(run.get() && isActive) {
    val pcm=queue.poll(100,java.util.concurrent.TimeUnit.MILLISECONDS) ?: continue
    queuedBytes.updateAndGet { maxOf(0,it-pcm.size) }
    val epoch=outputGeneration
    var offset=0
    while(offset<pcm.size && run.get() && epoch==outputGeneration) {
     val n=runCatching { synchronized(playbackLock) { if(run.get() && epoch==outputGeneration) output.write(pcm,offset,minOf(2400,pcm.size-offset),AudioTrack.WRITE_NON_BLOCKING) else 0 } }.getOrDefault(-1)
     if(n<0) { if(run.get()) onFailure?.invoke();break }; if(n==0) delay(5) else offset+=n
    }
    if(run.get()) onLevels?.invoke(0.0,level(pcm))
   }
  }
 }
 @Synchronized fun enqueue(pcm:ByteArray):Boolean {
  if(pcm.size>96000 || queuedBytes.get()+pcm.size>1048576) return false
  queuedBytes.addAndGet(pcm.size)
  if(queue.offer(pcm)) return true
  queuedBytes.addAndGet(-pcm.size);return false
 }
 fun clearPlayback() { synchronized(playbackLock) { outputGeneration++;queue.clear();queuedBytes.set(0);player?.pause();player?.flush();if(running.get()) player?.play() };onLevels?.invoke(0.0,0.0) }
 fun close() {
  lifecycle++;running.set(false);capture?.cancel();playback?.cancel();queue.clear();queuedBytes.set(0)
  runCatching { recorder?.stop() };runCatching { player?.stop() }
  echo?.release();echo=null
  devices?.let { runCatching { manager.unregisterAudioDeviceCallback(it) } };devices=null
  runCatching { legacyRoute?.close(restoreSpeakerphone=true) };legacyRoute=null
  if(android.os.Build.VERSION.SDK_INT>=31 && ownsRoute) runCatching { manager.clearCommunicationDevice() };ownsRoute=false
  priorMode?.let { runCatching { manager.mode=it } };priorMode=null
  focus?.let { runCatching { manager.abandonAudioFocusRequest(it) } };focus=null
  synchronized(captureLock) { recorder?.release();recorder=null };synchronized(playbackLock) { player?.release();player=null }
  onLevels?.invoke(0.0,0.0)
 }
 private fun routeAudio() {
  if(android.os.Build.VERSION.SDK_INT>=31) {
   val current=manager.communicationDevice
   val selected=selectCommunicationDevice(current,manager.availableCommunicationDevices,sameDevice={a,b -> a.id==b.id}) { it.type }
   if(selected!=null && current?.id!=selected.id && manager.setCommunicationDevice(selected)) ownsRoute=true
  } else legacyRoute?.devicesChanged()
 }
 private fun level(pcm:ByteArray):Double { var peak=0; for(i in 0 until pcm.size-1 step 2) { val value=((pcm[i].toInt() and 255) or (pcm[i+1].toInt() shl 8)).toShort().toInt();peak=maxOf(peak,kotlin.math.abs(value)) };return (peak/32768.0).coerceIn(0.0,1.0) }
}
