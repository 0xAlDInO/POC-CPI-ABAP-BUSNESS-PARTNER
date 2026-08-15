import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonBuilder

def Message processData(Message message) {
    def exception = message.getProperty("CamelExceptionCaught")
    def detail = exception?.message ?: "Erreur technique lors de l'appel RFC SAP."
    message.setBody(new JsonBuilder([
        BpParent: message.getProperty("original_bp_parent") ?: "",
        FirstName: message.getProperty("original_first_name") ?: "",
        LastName: message.getProperty("original_last_name") ?: "",
        BpContactId: "",
        StatusCode: "ERROR",
        StatusMessage: "Erreur d'intégration CPI → SAP RFC : ${detail}"
    ]).toString())
    message.setHeader("Content-Type", "application/json")
    message.setHeader("CamelHttpResponseCode", 502)
    return message
}
