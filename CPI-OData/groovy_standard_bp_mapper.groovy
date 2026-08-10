import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonSlurper;
import groovy.json.JsonBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def jsonSlurper = new JsonSlurper();
    def inputMap = [:];

    try {
        inputMap = jsonSlurper.parseText(body);
    } catch(Exception e) {
        return buildErrorResponse(message, "Le format du payload JSON envoyé est invalide : " + e.getMessage());
    }

    if (!(inputMap instanceof Map)) {
        return buildErrorResponse(message, "Le payload JSON doit être un objet.");
    }

    // Validation des champs obligatoires
    def missingFields = [];
    if (!inputMap.BpParent) missingFields.add("BpParent");
    if (!inputMap.FirstName) missingFields.add("FirstName");
    if (!inputMap.LastName) missingFields.add("LastName");

    if (missingFields.size() > 0) {
        return buildErrorResponse(message, "Champs obligatoires manquants : " + missingFields.join(", "));
    }

    // Normalisation des valeurs par défaut
    def bpCategory = inputMap.BpCategory ?: "1";
    def grouping   = inputMap.Grouping ?: "ZC";
    def bpRole     = inputMap.BpRole ?: "BUP001";

    // Sauvegarde des données initiales dans les propriétés Camel pour les étapes suivantes
    message.setProperty("prop_bp_parent", inputMap.BpParent);
    message.setProperty("prop_bp_role", bpRole);
    message.setProperty("prop_first_name", inputMap.FirstName);
    message.setProperty("prop_last_name", inputMap.LastName);
    message.setProperty("prop_date_from", inputMap.DateFrom ?: "");
    message.setProperty("prop_date_to", inputMap.DateTo ?: "");

    // Construction du payload JSON pour l'Appel 1: A_BusinessPartner (avec adresse imbriquée)
    def bpPayload = [
        "BusinessPartnerCategory": bpCategory,
        "BusinessPartnerGrouping": grouping,
        "FirstName": inputMap.FirstName,
        "LastName": inputMap.LastName
    ];

    // Ajout de l'adresse optionnelle
    def addressFields = ["Street", "HouseNumber", "PostalCode", "City", "Region", "Language"];
    def hasAddress = addressFields.any { inputMap[it] };

    if (hasAddress) {
        if (!inputMap.Country) {
            return buildErrorResponse(message, "Le pays (Country) est obligatoire lorsqu'une adresse est fournie.");
        }
        bpPayload["to_BusinessPartnerAddress"] = [
            [
                "Country": inputMap.Country.toUpperCase(),
                "StreetName": inputMap.Street ?: "",
                "HouseNumber": inputMap.HouseNumber ?: "",
                "PostalCode": inputMap.PostalCode ?: "",
                "CityName": inputMap.City ?: "",
                "Region": inputMap.Region ?: "",
                "Language": (inputMap.Language ?: "FR").toUpperCase()
            ]
        ];
    }

    // Mise à jour du message
    def jsonBuilder = new JsonBuilder(bpPayload);
    message.setBody(jsonBuilder.toString());
    message.setProperty("is_integration_failed", "false");

    message.setHeader("Content-Type", "application/json");
    message.setHeader("Accept", "application/json");

    return message;
}

def Message buildErrorResponse(Message message, String errorMessage) {
    def errorPayload = [
        "StatusCode": "ERROR",
        "StatusMessage": errorMessage
    ];
    def jsonBuilder = new JsonBuilder(errorPayload);
    message.setBody(jsonBuilder.toString());
    message.setProperty("is_integration_failed", "true");
    message.setHeader("CamelHttpResponseCode", 400);
    message.setHeader("Content-Type", "application/json");
    return message;
}
