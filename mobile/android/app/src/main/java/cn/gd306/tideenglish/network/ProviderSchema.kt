package cn.gd306.tideenglish.network
import kotlinx.serialization.json.*
/** The subset of JSON schema used by the app's structured learning helpers. */
internal fun matchesProviderSchema(value:JsonElement,schema:JsonObject,depth:Int=0):Boolean {
 if(depth>20) return false
 val enum=schema["enum"] as? JsonArray
 if(enum!=null && value !in enum) return false
 return when(schema.str("type")) {
  "object" -> {
   val obj=value as? JsonObject ?: return false
   val properties=schema["properties"] as? JsonObject ?: JsonObject(emptyMap())
   val required=schema["required"] as? JsonArray ?: JsonArray(emptyList())
   if(required.any { (it as? JsonPrimitive)?.contentOrNull !in obj }) return false
   if(schema["additionalProperties"]==JsonPrimitive(false) && obj.keys.any { it !in properties }) return false
   obj.all { (key,item) -> (properties[key] as? JsonObject)?.let { matchesProviderSchema(item,it,depth+1) } ?: true }
  }
  "array" -> {
   val array=value as? JsonArray ?: return false
   if(array.size<((schema["minItems"] as? JsonPrimitive)?.intOrNull ?: 0)) return false
   if(array.size>((schema["maxItems"] as? JsonPrimitive)?.intOrNull ?: Int.MAX_VALUE)) return false
   val items=schema["items"] as? JsonObject
   items==null || array.all { matchesProviderSchema(it,items,depth+1) }
  }
  "string" -> (value as? JsonPrimitive)?.isString==true
  "boolean" -> (value as? JsonPrimitive)?.let { !it.isString && it.booleanOrNull!=null }==true
  "number","integer" -> {
   val primitive=value as? JsonPrimitive ?: return false
   if(primitive.isString) return false
   val number=primitive.doubleOrNull ?: return false
   number.isFinite() && number>=((schema["minimum"] as? JsonPrimitive)?.doubleOrNull ?: Double.NEGATIVE_INFINITY) && number<=((schema["maximum"] as? JsonPrimitive)?.doubleOrNull ?: Double.POSITIVE_INFINITY) && (schema.str("type")!="integer" || number%1.0==0.0)
  }
  else -> false
 }
}
