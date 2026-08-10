import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    // Récupération de l'exception capturée
    def exception = message.getProperty("CamelExceptionCaught");
    def exceptionMessage = "Une erreur technique est survenue lors de l'orchestration OData SAP standard.";

    if (exception != null) {
        exceptionMessage = exception.getMessage() ?: exception.toString();
    }

    // Récupération éventuelle des informations mémorisées
    def bpParent = message.getProperty("prop_bp_parent") ?: "";
    def firstName = message.getProperty("prop_first_name") ?: "";
    def lastName = message.getProperty("prop_last_name") ?: "";
    def bpContact = message.getProperty("prop_bp_contact_created") ?: "";

    // Construction d'une réponse d'erreur unifiée
    def errorPayload = [
        "BpParent": bpParent,
        "FirstName": firstName,
        "LastName": lastName,
        "BpContactId": bpContact,
        "StatusCode": "ERROR",
        "StatusMessage": exceptionMessage
    ];

    def jsonBuilder = new JsonBuilder(errorPayload);
    message.setBody(jsonBuilder.toString());

    // Positionner des propriétés de contrôle pour le routeur CPI
    message.setProperty("is_integration_failed", "true");

    // HTTP 502 Bad Gateway ou 500 selon le cas pour notifier l'échec d'une étape
    message.setHeader("CamelHttpResponseCode", 502);
    message.setHeader("Content-Type", "application/json");

    return message;
}
