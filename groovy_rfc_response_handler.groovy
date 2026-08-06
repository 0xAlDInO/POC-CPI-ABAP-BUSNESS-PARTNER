import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonBuilder

def Message processData(Message message) {
    def xml = new XmlSlurper(false, false).parseText(message.getBody(String))
    def value = { String field ->
        def node = xml.'**'.find { it.name().toString().tokenize(':').last() == field }
        node ? node.text() : ""
    }
    def status = value("EV_STATUS_CODE")
    def contact = value("EV_BP_CONTACT")
    def description = value("EV_STATUS_MESSAGE")

    if (!(status in ["SUCCESS", "EXISTS", "LOCKED", "ERROR"])) {
        throw new IllegalStateException("Réponse RFC invalide : EV_STATUS_CODE absent ou inconnu.")
    }

    def httpStatus = status == "SUCCESS" ? 201 :
        (status == "EXISTS" ? 409 : (status == "LOCKED" ? 423 : 400))
    message.setBody(new JsonBuilder([
        BpParent: message.getProperty("original_bp_parent") ?: "",
        FirstName: message.getProperty("original_first_name") ?: "",
        LastName: message.getProperty("original_last_name") ?: "",
        BpContactId: contact,
        StatusCode: status,
        StatusMessage: description
    ]).toString())
    message.setHeader("Content-Type", "application/json")
    message.setHeader("CamelHttpResponseCode", httpStatus)
    return message
}
