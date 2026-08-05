import com.sap.gateway.ip.core.customdev.util.Message;
import java.util.HashMap;
import groovy.json.JsonSlurper;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    // Récupération du corps du message (Payload HTTP)
    def body = message.getBody(java.lang.String);

    // Initialisation du parser JSON
    def jsonSlurper = new JsonSlurper();
    def inputMap = [:];

    try {
        inputMap = jsonSlurper.parseText(body);
    } catch(Exception e) {
        // En cas d'erreur de parsing du JSON
        return buildErrorResponse(message, "ERROR", "Le format du payload JSON envoyé par l'expéditeur est invalide : " + e.getMessage());
    }

    if (!(inputMap instanceof Map)) {
        return buildErrorResponse(message, "ERROR", "Le payload JSON doit être un objet.");
    }

    // --- LOGIQUE DE VALIDATION TECHNIQUE (PRE-REQUIS CPI) ---
    def missingFields = [];
    if (!inputMap.BpParent) missingFields.add("BpParent");
    if (!inputMap.FirstName) missingFields.add("FirstName");
    if (!inputMap.LastName) missingFields.add("LastName");

    // Valeur par défaut cohérente avec le cas d'usage Contact Person.
    if (!inputMap.BpCategory) inputMap.BpCategory = "1";
    if (!inputMap.Grouping) inputMap.Grouping = "ZC";
    if (!inputMap.BpRole) inputMap.BpRole = "BUP001";

    def addressFields = ["Street", "HouseNumber", "PostalCode", "City", "Region", "Language"];
    def hasAddress = addressFields.any { inputMap[it] };
    if (hasAddress && !inputMap.Country) missingFields.add("Country");

    // Si des champs obligatoires sont manquants, on arrête le flux immédiatement
    if (missingFields.size() > 0) {
        String errMsg = "Champs obligatoires manquants dans le payload : " + missingFields.join(", ");
        return buildErrorResponse(message, "ERROR", errMsg);
    }

    // --- FORMATAGE ET ENRICHISSEMENT DES DONNÉES ---
    // Exemple : Forcer le pays en majuscules (ex: 'fr' -> 'FR')
    if (inputMap.Country) {
        inputMap.Country = inputMap.Country.toUpperCase();
    }

    // Injection des dates par défaut si non fournies
    if (!inputMap.DateFrom) {
        // Date actuelle au format ISO requis par l'OData (ex: YYYY-MM-DDT00:00:00)
        def currentDate = new Date().format("yyyy-MM-dd'T'HH:mm:ss");
        inputMap.DateFrom = currentDate;
    }

    // Mise à jour du corps du message traité à envoyer à SAP
    def jsonBuilder = new JsonBuilder(inputMap);
    message.setBody(jsonBuilder.toString());

    // Conservés pour permettre au gestionnaire d'erreur de retourner
    // un contrat de réponse homogène.
    message.setProperty("original_bp_parent", inputMap.BpParent);
    message.setProperty("original_first_name", inputMap.FirstName);
    message.setProperty("original_last_name", inputMap.LastName);

    // Définition des headers requis pour l'appel de l'OData SAP Gateway
    message.setHeader("Content-Type", "application/json");
    message.setHeader("Accept", "application/json");

    return message;
}

/**
 * Méthode utilitaire pour générer une réponse d'erreur propre en cas d'échec
 */
def Message buildErrorResponse(Message message, String statusCode, String errorMessage) {
    def errorPayload = [
        "BpParent": "",
        "BpCategory": "1",
        "Grouping": "ZC",
        "BpRole": "BUP001",
        "FirstName": "",
        "LastName": "",
        "BpContactId": "",
        "StatusCode": statusCode,
        "StatusMessage": errorMessage
    ];

    def jsonBuilder = new JsonBuilder(errorPayload);
    message.setBody(jsonBuilder.toString());

    // Positionner des propriétés de contrôle pour le routeur CPI
    message.setProperty("is_integration_failed", "true");
    message.setHeader("CamelHttpResponseCode", 400);
    message.setHeader("Content-Type", "application/json");

    return message;
}
