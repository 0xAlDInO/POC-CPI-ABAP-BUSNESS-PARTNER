import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonSlurper;
import groovy.json.JsonBuilder;
import java.text.SimpleDateFormat;
import java.util.Date;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def jsonSlurper = new JsonSlurper();
    def responseMap = [:];

    try {
        responseMap = jsonSlurper.parseText(body);
    } catch(Exception e) {
        throw new RuntimeException("Erreur lors de la lecture de la réponse de création de rôle : " + e.getMessage());
    }

    // Récupération des propriétés mémorisées
    def bpParent = message.getProperty("prop_bp_parent");
    def bpContact = message.getProperty("prop_bp_contact_created");
    def dateFromStr = message.getProperty("prop_date_from");
    def dateToStr = message.getProperty("prop_date_to");

    // Calcul des dates au format OData V2 JSON (ex: /Date(1785888000000)/)
    def odataDateFrom = convertToODataDate(dateFromStr, false);
    def odataDateTo   = convertToODataDate(dateToStr, true);

    // Construction du payload pour l'Appel 3: A_BusinessPartnerContact
    def relationPayload = [
        "BusinessPartnerCompany": bpParent,
        "BusinessPartnerPerson": bpContact,
        "RelationshipCategory": "BUR001",
        "ValidityStartDate": odataDateFrom,
        "ValidityEndDate": odataDateTo
    ];

    def jsonBuilder = new JsonBuilder(relationPayload);
    message.setBody(jsonBuilder.toString());

    message.setHeader("Content-Type", "application/json");
    message.setHeader("Accept", "application/json");

    return message;
}

def String convertToODataDate(String dateStr, boolean isEndDate) {
    if (!dateStr) {
        if (isEndDate) {
            // Par défaut : 31 Décembre 9999 (253402300799000 ms)
            return "/Date(253402300799000)/";
        } else {
            // Par défaut : Date actuelle
            return "/Date(" + System.currentTimeMillis() + ")/";
        }
    }

    try {
        def sdf = new SimpleDateFormat("yyyy-MM-dd");
        Date date = sdf.parse(dateStr);
        return "/Date(" + date.getTime() + ")/";
    } catch(Exception e) {
        throw new RuntimeException("Format de date invalide : '" + dateStr + "'. Attendu : YYYY-MM-DD.");
    }
}
