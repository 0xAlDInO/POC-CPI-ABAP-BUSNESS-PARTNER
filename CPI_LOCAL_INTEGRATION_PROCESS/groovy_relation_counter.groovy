import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonSlurper

def Message processData(Message message) {
    def body = message.getBody(String)

    try {
        def json = new JsonSlurper().parseText(body)
        def count = 0

        if (json.relations instanceof List) {
            count = json.relations.size()
        } else if (json.contacts instanceof List) {
            count = json.contacts.size()
        }

        message.setProperty("RelationCount", count)
        message.setProperty("HasRelations", count > 0 ? "true" : "false")

    } catch (Exception e) {
        message.setProperty("RelationCount", 0)
        message.setProperty("HasRelations", "false")
    }

    return message
}
