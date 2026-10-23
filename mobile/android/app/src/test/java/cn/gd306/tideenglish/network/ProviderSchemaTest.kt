package cn.gd306.tideenglish.network
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
class ProviderSchemaTest {
 @Test fun validatesRequiredTypesAndBoundsWithoutCoercingStrings() {
  val schema=Json.parseToJsonElement("""{"type":"object","properties":{"score":{"type":"integer","minimum":0,"maximum":5}},"required":["score"],"additionalProperties":false}""").jsonObject
  assertTrue(matchesProviderSchema(Json.parseToJsonElement("""{"score":3}"""),schema))
  listOf("{}","""{"score":"3"}""","""{"score":6}""","""{"score":2.5}""","""{"score":3,"extra":1}""").forEach { assertFalse(matchesProviderSchema(Json.parseToJsonElement(it),schema)) }
 }
}
