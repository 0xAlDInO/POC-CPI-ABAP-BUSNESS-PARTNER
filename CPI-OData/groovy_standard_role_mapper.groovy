import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonSlurper;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def jsonSlurper = new JsonSlurper();
    def responseMap = [:];

    try {
        responseMap = jsonSlurper.parseText(body);
    } catch(Exception e) {
        throw new RuntimeException("Erreur lors de la lecture de la réponse OData A_BusinessPartner : " + e.getMessage());
    }

    // Récupération du BusinessPartner ID généré par SAP
    def bpContactCreated = responseMap.d?.BusinessPartner;

    if (!bpContactCreated) {
        throw new RuntimeException("L'API OData SAP n'a retourné aucun numéro de BusinessPartner valide dans la réponse.");
    }

    // Sauvegarde de l'ID créé dans une propriété globale
    message.setProperty("prop_bp_contact_created", bpContactCreated);

    // Récupération du rôle désiré (stocké à l'étape 1)
    def bpRole = message.getProperty("prop_bp_role");

    // Construction du payload pour l'Appel 2: A_BusinessPartnerRole
    def rolePayload = [
        "BusinessPartner": bpContactCreated,
        "BusinessPartnerRole": bpRole
    ];

    def jsonBuilder = new JsonBuilder(rolePayload);
    message.setBody(jsonBuilder.toString());

    message.setHeader("Content-Type", "application/json");
    message.setHeader("Accept", "application/json");

    return message;
}
