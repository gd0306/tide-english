package cn.gd306.tideenglish.network
import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
class EmailAccountClientTest {
 @Test fun challengeUsesFixedPathAndDoesNotFollowRedirects()=runTest {
  var calls=0;val transport=OkHttpClient.Builder().addInterceptor { chain->calls++;assertEquals("https://api.gd306.cn/v1/email-auth/challenge",chain.request().url.toString());assertNull(chain.request().header("Authorization"));Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(302).message("redirect").header("Location","https://example.org/").body("{}".toResponseBody()).build() }.build()
  try{EmailAccountClient(EmailAccountConfiguration(),transport).challenge("a@example.com");fail("accepted redirect")}catch(e:EmailAccountException){assertEquals(EmailAccountFailure.Unavailable,e.failure)};assertEquals(1,calls)
 }
 @Test fun rejectsExtraFieldsAndRedactsRawErrors()=runTest {
  val transport=OkHttpClient.Builder().addInterceptor { chain->Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(202).message("ok").body("""{"challengeID":"12345678-1234-4234-8234-123456789012","expiresInSeconds":300,"retryAfterSeconds":60,"secret":"private"}""".toResponseBody()).build() }.build()
  try{EmailAccountClient(EmailAccountConfiguration(),transport).challenge("a@example.com");fail("accepted unknown field")}catch(e:EmailAccountException){assertEquals(EmailAccountFailure.InvalidResponse,e.failure);assertFalse(e.toString().contains("private"))}
 }
 @Test fun configurationRejectsCredentialPathsAndCleartext(){for(v in listOf("http://api.gd306.cn","https://u:p@api.gd306.cn","https://api.gd306.cn/path","https://api.gd306.cn?x=y"))assertThrows(EmailAccountException::class.java){EmailAccountConfiguration(v)}}
}
