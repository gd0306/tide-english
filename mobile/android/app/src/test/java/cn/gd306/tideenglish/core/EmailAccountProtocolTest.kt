package cn.gd306.tideenglish.core
import org.junit.Assert.*
import org.junit.Test
class EmailAccountProtocolTest {
 @Test fun normalizesAndRejectsUnsafeAddresses() { assertEquals("a@example.com", EmailAccountValidation.email(" A@EXAMPLE.COM ")); for (v in listOf("a@localhost", "a\n@example.com", "a..b@example.com")) assertThrows(EmailAccountException::class.java) { EmailAccountValidation.email(v) } }
 @Test fun rotationPreservesOriginalDeadlineAndRejectsTokenReuse() { val e = EmailAccountExchange("12345678-1234-4234-8234-123456789012", "a@example.com", "a".repeat(43), "b".repeat(43),900,2000); val s=EmailAccountSession.create(e,"scope",1000); assertTrue(s.canRefresh("scope",1500)); assertFalse(s.canRefresh("other",1500)); assertThrows(EmailAccountException::class.java) { EmailAccountSession.create(e,"scope",1500,s) }; val rotated=EmailAccountSession.create(e.copy(accessToken="c".repeat(43),refreshToken="d".repeat(43)),"scope",1500,s); assertEquals(3000L,rotated.refreshExpiresAt) }
}
