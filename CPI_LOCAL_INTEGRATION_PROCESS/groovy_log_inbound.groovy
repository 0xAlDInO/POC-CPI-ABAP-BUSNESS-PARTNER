import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

def Message processData(Message message) {
    def body = message.getBody(String)

    // Set Log Inbound property
    def messageLog = messageLogFactory.getMessageLog(message)
    if (messageLog != null) {
        messageLog.addAttachmentAsString("Inbound_Payload", body, "application/json")
    }

    // Store original body in camel property for backup
    message.setProperty("OriginalInboundPayload", body)

    // Parse JSON to extract header info or type
    try {
        def json = new JsonSlurper().parseText(body)
        def payloadType = json.businessPartner ? "BP" : (json.relations ? "BP Relations" : "Unknown")
        message.setProperty("PayloadType", payloadType)
    } catch (Exception e) {
        message.setProperty("PayloadType", "Invalid_JSON")
    }

    return message
}
