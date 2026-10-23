package cn.gd306.tideenglish.core

import kotlinx.serialization.Serializable
import java.net.URI

enum class EmailAccountFailure : java.io.Serializable { InvalidEmail, InvalidCode, InvalidSession, RateLimited, DeliveryUnavailable, Transport, InvalidResponse, Unavailable, SecureStorage, RenewalUncertain, RevocationUnconfirmed }
class EmailAccountException(val failure: EmailAccountFailure) : Exception(failure.name)
internal fun fail(f: EmailAccountFailure): Nothing = throw EmailAccountException(f)
object EmailAccountValidation {
 fun email(value: String): String {
  if (value.any { it.code !in 32..126 }) fail(EmailAccountFailure.InvalidEmail)
  val email=value.trim().lowercase(java.util.Locale.ROOT); val parts=email.split('@')
  if (email.length>254 || parts.size!=2 || parts[0].length !in 1..64 || !Regex("[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*").matches(parts[0])) fail(EmailAccountFailure.InvalidEmail)
  val labels=parts[1].split('.'); if (labels.size<2 || labels.any { !Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?").matches(it) }) fail(EmailAccountFailure.InvalidEmail)
  return email
 }
 fun token(v: String)=Regex("[A-Za-z0-9_-]{43}").matches(v)
 fun code(v: String)=Regex("[0-9]{6}").matches(v)
 fun identity(v: String)=Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}").matches(v)
}
class EmailAccountConfiguration(apiURL: String = "https://api.gd306.cn") {
 val origin: String
 val storageScope: String get()="tide.email-account.v1|$origin"
 init { val u=try { URI(apiURL) } catch (_: Exception) { fail(EmailAccountFailure.Unavailable) }; if(u.scheme?.lowercase()!="https" || u.host.isNullOrEmpty() || u.rawUserInfo!=null || u.rawQuery!=null || u.rawFragment!=null || u.rawPath !in listOf("","/") || u.port !in listOf(-1,443)) fail(EmailAccountFailure.Unavailable); origin="https://${u.host.lowercase(java.util.Locale.ROOT)}" }
}
@Serializable data class EmailAccountChallenge(val challengeID:String,val expiresInSeconds:Int,val retryAfterSeconds:Int) { fun validate() { if(!EmailAccountValidation.identity(challengeID)||expiresInSeconds!=300||retryAfterSeconds!=60) fail(EmailAccountFailure.InvalidResponse) } }
@Serializable data class EmailAccountExchange(val accountID:String,val email:String,val accessToken:String,val refreshToken:String,val expiresInSeconds:Int,val refreshExpiresInSeconds:Int) {
 override fun toString()="EmailAccountExchange(redacted)"
 fun validate() { if(!EmailAccountValidation.identity(accountID)||runCatching { EmailAccountValidation.email(email) }.getOrNull()!=email||!EmailAccountValidation.token(accessToken)||!EmailAccountValidation.token(refreshToken)||accessToken==refreshToken||expiresInSeconds!=900||refreshExpiresInSeconds !in 1..2592000) fail(EmailAccountFailure.InvalidResponse) }
}
@Serializable data class EmailAccountSession(val accountID:String,val email:String,val accessToken:String,val refreshToken:String,val expiresAt:Long,val refreshExpiresAt:Long,val scope:String) {
 override fun toString()="EmailAccountSession(redacted)"
 fun canRefresh(scope:String,now:Long):Boolean = this.scope==scope && EmailAccountValidation.identity(accountID) && runCatching { EmailAccountValidation.email(email) }.getOrNull()==email && EmailAccountValidation.token(accessToken)&&EmailAccountValidation.token(refreshToken)&&accessToken!=refreshToken&&expiresAt-now<=900&&refreshExpiresAt>now&&refreshExpiresAt-now<=2592000
 fun accessUsable(scope:String,now:Long)=canRefresh(scope,now)&&expiresAt>now
 companion object { fun create(e:EmailAccountExchange,scope:String,now:Long,previous:EmailAccountSession?=null):EmailAccountSession { e.validate(); if(scope.isEmpty()||now<0) fail(EmailAccountFailure.InvalidResponse); if(previous!=null && (!previous.canRefresh(scope,now)||previous.accountID!=e.accountID||previous.email!=e.email||setOf(previous.accessToken,previous.refreshToken).any { it==e.accessToken||it==e.refreshToken })) fail(EmailAccountFailure.InvalidResponse); return EmailAccountSession(e.accountID,e.email,e.accessToken,e.refreshToken,now+900,minOf(previous?.refreshExpiresAt?:Long.MAX_VALUE,now+e.refreshExpiresInSeconds),scope) } }
}
interface EmailAccountService {
 suspend fun challenge(email:String):EmailAccountChallenge
 suspend fun verify(challengeID:String,code:String):EmailAccountExchange
 suspend fun refresh(refreshToken:String):EmailAccountExchange
 suspend fun signOut(refreshToken:String)
 suspend fun delete(session:EmailAccountSession,challengeID:String,code:String)
}
interface EmailAccountStorage { suspend fun read():EmailAccountSession?; suspend fun save(session:EmailAccountSession); suspend fun clear(); suspend fun markUncertain(); suspend fun isUncertain():Boolean }
