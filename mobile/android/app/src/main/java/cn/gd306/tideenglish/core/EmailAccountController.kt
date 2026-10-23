package cn.gd306.tideenglish.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex

data class EmailAccountState(val email:String?=null,val pendingEmail:String?=null,val busy:Boolean=false,val challengeReady:Boolean=false,val deleting:Boolean=false,val retryAt:Long=0,val challengeExpiresAt:Long=0,val failure:EmailAccountFailure?=null,val completed:String?=null)
/** Owns only optional account identity. Never receives a learning repository or model credentials. */
class EmailAccountController(private val service:EmailAccountService,private val storage:EmailAccountStorage,private val scope:String,private val now:()->Long={System.currentTimeMillis()/1000}) {
 private val mutation=Mutex(); private var session:EmailAccountSession?=null; private var challenge:EmailAccountChallenge?=null; private var challengeEmail:String?=null
 private val mutable=MutableStateFlow(EmailAccountState()); val state:StateFlow<EmailAccountState> = mutable
 private suspend fun action(block:suspend ()->Unit) { if(!mutation.tryLock())return; mutable.value=mutable.value.copy(busy=true,failure=null,completed=null); try { block() } catch(e:CancellationException){throw e} catch(e:Exception){mutable.value=mutable.value.copy(failure=(e as? EmailAccountException)?.failure?:EmailAccountFailure.Unavailable)} finally {mutable.value=mutable.value.copy(busy=false); mutation.unlock()} }
 suspend fun restore()=action { session=null; mutable.value=mutable.value.copy(email=null); if(storage.isUncertain()){storage.clear(); mutable.value=mutable.value.copy(failure=EmailAccountFailure.RenewalUncertain);return@action}; val s=storage.read()?:return@action; if(!s.canRefresh(scope,now())){storage.clear();return@action}; session=s; mutable.value=mutable.value.copy(email=s.email); if(!s.accessUsable(scope,now()))refresh() }
 suspend fun sendCode(email:String,deleting:Boolean=false)=action {
  if(now()<mutable.value.retryAt)throw EmailAccountException(EmailAccountFailure.RateLimited)
  val normalized=EmailAccountValidation.email(if(deleting)session?.email?:throw EmailAccountException(EmailAccountFailure.InvalidSession) else email)
  // A new attempt invalidates the prior challenge even when delivery cannot be confirmed.
  challenge=null; challengeEmail=null; mutable.value=mutable.value.copy(challengeReady=false,pendingEmail=normalized,deleting=deleting,retryAt=now()+60)
  val result=service.challenge(normalized); result.validate(); challenge=result; challengeEmail=normalized
  mutable.value=mutable.value.copy(challengeReady=true,challengeExpiresAt=now()+result.expiresInSeconds)
 }
 suspend fun verify(code:String)=action {
  val ch=challenge?:throw EmailAccountException(EmailAccountFailure.InvalidCode)
  if(!EmailAccountValidation.code(code)||now()>=mutable.value.challengeExpiresAt)throw EmailAccountException(EmailAccountFailure.InvalidCode)
  if(mutable.value.deleting){var s=session?:throw EmailAccountException(EmailAccountFailure.InvalidSession); if(!s.accessUsable(scope,now())) {refresh();s=session?:throw EmailAccountException(EmailAccountFailure.InvalidSession)}; service.delete(s,ch.challengeID,code); session=null; reset("deleted"); storage.markUncertain(); storage.clear()}
  else {val e=service.verify(ch.challengeID,code); if(e.email!=challengeEmail)throw EmailAccountException(EmailAccountFailure.InvalidResponse); val s=EmailAccountSession.create(e,scope,now()); try {storage.save(s)}catch(e:Exception){runCatching { storage.markUncertain() }; runCatching {service.signOut(s.refreshToken)}; throw EmailAccountException(EmailAccountFailure.SecureStorage)};session=s;reset("signedIn");mutable.value=mutable.value.copy(email=s.email)}
 }
 private suspend fun refresh() {
  val previous=session?:throw EmailAccountException(EmailAccountFailure.InvalidSession)
  storage.markUncertain() // A lost rotating response must never permit retrying the consumed token.
  try {val exchange=service.refresh(previous.refreshToken);val next=EmailAccountSession.create(exchange,scope,now(),previous);storage.save(next);session=next}
  catch(e:Exception){session=null;mutable.value=mutable.value.copy(email=null);runCatching {storage.clear()};if(e is CancellationException)throw e;throw EmailAccountException(EmailAccountFailure.RenewalUncertain)}
 }
 suspend fun signOut()=action {
  val old=session; storage.markUncertain();session=null;reset("signedOut");storage.clear()
  if(old!=null)try {service.signOut(old.refreshToken)}catch(e:Exception){if(e is CancellationException)throw e;throw EmailAccountException(EmailAccountFailure.RevocationUnconfirmed)}
 }
 fun invalidateChallenge(){if(!mutable.value.busy){challenge=null;challengeEmail=null;mutable.value=mutable.value.copy(challengeReady=false,pendingEmail=null)}}
 fun cancelDeletion(){if(!mutable.value.busy){challenge=null;challengeEmail=null;mutable.value=mutable.value.copy(deleting=false,challengeReady=false)}}
 private fun reset(completed:String){challenge=null;challengeEmail=null;mutable.value=EmailAccountState(retryAt=mutable.value.retryAt,completed=completed,busy=true)}
}
