package cn.gd306.tideenglish.network

import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class EmailAccountClient internal constructor(private val configuration:EmailAccountConfiguration, transport:OkHttpClient):EmailAccountService {
 constructor(configuration:EmailAccountConfiguration=EmailAccountConfiguration()):this(configuration,OkHttpClient())
 private val client=transport.newBuilder().followRedirects(false).followSslRedirects(false).cookieJar(CookieJar.NO_COOKIES).cache(null).authenticator(Authenticator.NONE).proxyAuthenticator(Authenticator.NONE).retryOnConnectionFailure(false).callTimeout(25,TimeUnit.SECONDS).build()
 private val json=Json { ignoreUnknownKeys=false; coerceInputValues=false }
 override suspend fun challenge(email:String):EmailAccountChallenge = decode<EmailAccountChallenge>(request("POST","email-auth/challenge",buildJsonObject { put("email",EmailAccountValidation.email(email)) },expected=202)).also { it.validate() }
 override suspend fun verify(challengeID:String,code:String):EmailAccountExchange { validateCode(challengeID,code); return decode<EmailAccountExchange>(request("POST","email-auth/verify",buildJsonObject { put("challengeID",challengeID);put("code",code) })).also { it.validate() } }
 override suspend fun refresh(refreshToken:String):EmailAccountExchange { if(!EmailAccountValidation.token(refreshToken)) throw EmailAccountException(EmailAccountFailure.InvalidSession); return decode<EmailAccountExchange>(request("POST","email-auth/refresh",buildJsonObject { put("refreshToken",refreshToken) })).also { it.validate() } }
 override suspend fun signOut(refreshToken:String) { if(!EmailAccountValidation.token(refreshToken)) throw EmailAccountException(EmailAccountFailure.InvalidSession); val r=request("POST","email-auth/sign-out",buildJsonObject { put("refreshToken",refreshToken) }); if(r!=buildJsonObject { put("signedOut",true) }) throw EmailAccountException(EmailAccountFailure.InvalidResponse) }
 override suspend fun delete(session:EmailAccountSession,challengeID:String,code:String) { validateCode(challengeID,code); if(!session.accessUsable(configuration.storageScope,System.currentTimeMillis()/1000)) throw EmailAccountException(EmailAccountFailure.InvalidSession); val r=request("DELETE","email-account",buildJsonObject { put("challengeID",challengeID);put("code",code) },session.accessToken); if(r!=buildJsonObject { put("deleted",true) }) throw EmailAccountException(EmailAccountFailure.InvalidResponse) }
 private fun validateCode(id:String,code:String) { if(!EmailAccountValidation.identity(id)||!EmailAccountValidation.code(code)) throw EmailAccountException(EmailAccountFailure.InvalidCode) }
 private inline fun <reified T> decode(o:JsonObject):T=try { json.decodeFromJsonElement<T>(o) } catch(_:Exception) { throw EmailAccountException(EmailAccountFailure.InvalidResponse) }
 private suspend fun request(method:String,path:String,body:JsonObject,token:String?=null,expected:Int=200):JsonObject {
  val req=Request.Builder().url(configuration.origin+"/v1/"+path).header("Accept","application/json").header("Cache-Control","no-store").apply { token?.let { header("Authorization","Bearer $it") } }.method(method,body.toString().toRequestBody("application/json".toMediaType())).build()
  return suspendCancellableCoroutine { c -> val call=client.newCall(req); c.invokeOnCancellation { call.cancel() }; call.enqueue(object:Callback {
   override fun onFailure(call:Call,e:IOException) { if(c.isActive)c.resumeWithException(EmailAccountException(EmailAccountFailure.Transport)) }
   override fun onResponse(call:Call,response:Response) { try { val result=response.use { r -> val b=r.body?:throw EmailAccountException(EmailAccountFailure.InvalidResponse); if(b.contentLength()>16384)throw EmailAccountException(EmailAccountFailure.InvalidResponse); val source=b.source(); if(source.request(16385))throw EmailAccountException(EmailAccountFailure.InvalidResponse); val parsed=try { json.parseToJsonElement(source.readUtf8()).jsonObject }catch(_:Exception){throw EmailAccountException(EmailAccountFailure.InvalidResponse)}; if(r.code!=expected) { val code=(parsed["error"] as? JsonObject)?.get("code")?.jsonPrimitive?.contentOrNull; throw EmailAccountException(when(code){"invalid_code"->EmailAccountFailure.InvalidCode;"invalid_session"->EmailAccountFailure.InvalidSession;"rate_limited"->EmailAccountFailure.RateLimited;"email_delivery_unavailable"->EmailAccountFailure.DeliveryUnavailable;else->EmailAccountFailure.Unavailable}) }; parsed }; if(c.isActive)c.resume(result) } catch(e:Exception) { if(c.isActive)c.resumeWithException(e as? EmailAccountException?:EmailAccountException(EmailAccountFailure.InvalidResponse)) } }
  }) }
 }
}
