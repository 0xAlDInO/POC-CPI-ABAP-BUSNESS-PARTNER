import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonBuilder;
import groovy.json.JsonSlurper;

def Message processData(Message message) {
    // Récupération de l'exception levée lors de l'appel OData
    def ex = message.getProperty("CamelExceptionCaught");
    String errorMsg = "Une erreur inattendue est survenue lors de l'intégration dans SAP S/4HANA.";
    String errorDetail = "";

    if (ex != null) {
        errorMsg = ex.getMessage();
        // Essayer de récupérer le corps de la réponse d'erreur HTTP de SAP Gateway
        if (ex.hasProperty("responseBody") && ex.responseBody != null) {
            errorDetail = ex.responseBody;
        }
    }

    // Extraction et nettoyage du message d'erreur OData si disponible
    def parsedMessage = errorMsg;
    if (errorDetail) {
        try {
            def slurper = new JsonSlurper();
            def parsedJson = slurper.parseText(errorDetail);
            if (parsedJson.error && parsedJson.error.message && parsedJson.error.message.value) {
                parsedMessage = parsedJson.error.message.value;
            }
        } catch(Exception e) {
            parsedMessage = errorDetail; // Fallback si non-JSON
        }
    }

    // Construction d'une réponse synchrone formatée au format de l'interface
    def responsePayload = [
        "BpParent": message.getProperty("original_bp_parent") ?: "",
        "FirstName": message.getProperty("original_first_name") ?: "",
        "LastName": message.getProperty("original_last_name") ?: "",
        "BpContactId": "",
        "StatusCode": "ERROR",
        "StatusMessage": "Erreur d'intégration CPI -> SAP : " + parsedMessage
    ];

    def jsonBuilder = new JsonBuilder(responsePayload);
    message.setBody(jsonBuilder.toString());

    // Configurer les headers HTTP de retour
    message.setHeader("Content-Type", "application/json");
    message.setHeader("CamelHttpResponseCode", 500);

    return message;
}
