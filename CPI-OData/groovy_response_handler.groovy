import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonBuilder;
import groovy.json.JsonSlurper;

/**
 * À placer après l'adaptateur OData V2, sur le chemin de succès.
 * Le CREATE OData peut répondre 201 ; le contrat de l'interface CPI expose
 * systématiquement 200 lorsque SAP a retourné un statut fonctionnel.
 */
def Message processData(Message message) {
    def body = message.getBody(java.lang.String);

    try {
        def response = new JsonSlurper().parseText(body);
        // Les réponses OData V2 sont normalement encapsulées sous "d".
        if (response instanceof Map && response.d instanceof Map) {
            response = response.d;
        }

        if (!(response instanceof Map) || !(response.StatusCode in ["SUCCESS", "EXISTS", "ERROR"])) {
            throw new IllegalStateException("Réponse fonctionnelle OData invalide.");
        }

        message.setBody(new JsonBuilder(response).toString());
        message.setHeader("Content-Type", "application/json");
        message.setHeader("CamelHttpResponseCode", 200);
    } catch (Exception e) {
        message.setBody(new JsonBuilder([
            "BpParent": message.getProperty("original_bp_parent") ?: "",
            "FirstName": message.getProperty("original_first_name") ?: "",
            "LastName": message.getProperty("original_last_name") ?: "",
            "BpContactId": "",
            "StatusCode": "ERROR",
            "StatusMessage": "Réponse invalide reçue de SAP : " + e.getMessage()
        ]).toString());
        message.setHeader("Content-Type", "application/json");
        message.setHeader("CamelHttpResponseCode", 500);
    }

    return message;
}
