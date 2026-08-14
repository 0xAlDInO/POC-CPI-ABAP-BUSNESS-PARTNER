import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

def Message processData(Message message) {
    def originalPayload = message.getProperty("OriginalInboundPayload")
    def bpResponse = message.getBody(String)

    def responseMap = [:]

    try {
        def jsonResp = new JsonSlurper().parseText(bpResponse)
        responseMap.status = "SUCCESS"
        responseMap.businessPartner = jsonResp
        responseMap.processedAt = new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone("UTC"))
    } catch (Exception e) {
        responseMap.status = "PROCESSED_WITH_WARNINGS"
        responseMap.businessPartnerDetails = bpResponse
    }

    message.setBody(JsonOutput.toJson(responseMap))
    message.setHeader("Content-Type", "application/json")
    message.setHeader("CamelHttpResponseCode", 201)

    return message
}
