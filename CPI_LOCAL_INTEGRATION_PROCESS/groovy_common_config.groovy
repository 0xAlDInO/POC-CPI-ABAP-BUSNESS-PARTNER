import com.sap.gateway.ip.core.customdev.util.Message

def Message processData(Message message) {
    // Set common configuration properties used in routing and delay steps
    message.setProperty("PreExitEnabled", "false")
    message.setProperty("MaxRetryAttempts", "3")
    message.setProperty("DelayDurationMillis", "1000")

    // Header for HTTP Status Code management
    message.setHeader("CamelHttpResponseCode", 200)

    return message
}
