import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    // Récupération des propriétés globales
    def bpParent = message.getProperty("prop_bp_parent");
    def bpContact = message.getProperty("prop_bp_contact_created");
    def firstName = message.getProperty("prop_first_name");
    def lastName = message.getProperty("prop_last_name");

    // Construction d'une réponse unifiée et homogène pour le client
    def successPayload = [
        "BpParent": bpParent,
        "FirstName": firstName,
        "LastName": lastName,
        "BpContactId": bpContact,
        "StatusCode": "SUCCESS",
        "StatusMessage": "Le contact a été créé avec succès, s'est vu affecter son rôle et a été rattaché au BP Parent " + bpParent + "."
    ];

    def jsonBuilder = new JsonBuilder(successPayload);
    message.setBody(jsonBuilder.toString());

    // Status HTTP 201 Created pour indiquer le succès des trois étapes
    message.setHeader("CamelHttpResponseCode", 201);
    message.setHeader("Content-Type", "application/json");

    return message;
}
