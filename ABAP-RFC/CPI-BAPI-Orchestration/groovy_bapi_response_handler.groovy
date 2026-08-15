import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def xmlResponse = new XmlSlurper(false, false).parseText(body);

    // Extraction et contrôle des retours de BAPI_TRANSACTION_COMMIT
    def errorNodes = xmlResponse.RETURN.findAll {
        it.TYPE.text() in ["E", "A", "X"]
    }
    if (errorNodes && errorNodes.size() > 0) {
        def errMsg = errorNodes.collect { it.MESSAGE.text() }.join(" | ");
        throw new RuntimeException("Échec du Commit transactionnel SAP : " + errMsg);
    }

    // Récupération des propriétés mémorisées
    def bpParent      = message.getProperty("bapi_prop_bp_parent");
    def bpContact     = message.getProperty("bapi_prop_bp_contact_created");
    def firstName     = message.getProperty("bapi_prop_first_name");
    def lastName      = message.getProperty("bapi_prop_last_name");

    // Construction d'une réponse de succès unifiée et homogène pour le client
    def successPayload = [
        "BpParent": bpParent,
        "FirstName": firstName,
        "LastName": lastName,
        "BpContactId": bpContact,
        "StatusCode": "SUCCESS",
        "StatusMessage": "Le contact BP " + bpContact + " a été créé, son rôle attribué, et la relation de contact BUR001 validée avec succès."
    ];

    def jsonBuilder = new JsonBuilder(successPayload);
    message.setBody(jsonBuilder.toString());

    // Status HTTP 201 Created pour indiquer le succès de l'orchestration transactionnelle
    message.setHeader("CamelHttpResponseCode", 201);
    message.setHeader("Content-Type", "application/json");

    return message;
}

/**
 * Gestionnaire d'erreur unifié à utiliser dans l'Exception Subprocess
 */
def Message handleError(Message message) {
    def exception = message.getProperty("CamelExceptionCaught");
    def exceptionMessage = "Échec de l'orchestration transactionnelle des BAPIs standards.";

    if (exception != null) {
        exceptionMessage = exception.getMessage() ?: exception.toString();
    }

    // Récupération des propriétés existantes si définies
    def bpParent  = message.getProperty("bapi_prop_bp_parent") ?: "";
    def bpContact = message.getProperty("bapi_prop_bp_contact_created") ?: "";
    def firstName = message.getProperty("bapi_prop_first_name") ?: "";
    def lastName  = message.getProperty("bapi_prop_last_name") ?: "";

    // Payload d'erreur homogène
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

    // Statut HTTP 502 Bad Gateway
    message.setHeader("CamelHttpResponseCode", 502);
    message.setHeader("Content-Type", "application/json");

    return message;
}
