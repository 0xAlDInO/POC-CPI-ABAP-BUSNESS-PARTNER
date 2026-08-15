import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.xml.MarkupBuilder;
import java.text.SimpleDateFormat;
import java.util.Date;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def xmlResponse = new XmlSlurper(false, false).parseText(body);

    // Extraction et contrôle des retours de l'étape 2 (Ajout de rôle)
    checkBapiReturn(xmlResponse);

    // Récupération des propriétés mémorisées
    def bpParent  = message.getProperty("bapi_prop_bp_parent");
    def bpContact = message.getProperty("bapi_prop_bp_contact_created");
    def dateFrom  = message.getProperty("bapi_prop_date_from");
    def dateTo    = message.getProperty("bapi_prop_date_to");

    // Normalisation des dates au format technique SAP (AAAAMMJJ)
    def sapDateFrom = convertToSapDate(dateFrom, false);
    def sapDateTo   = convertToSapDate(dateTo, true);

    // Construction du XML RFC pour BAPI_BUPR_CONTP_CREATE
    def writer = new StringWriter();
    def xml = new MarkupBuilder(writer);

    xml.BAPI_BUPR_CONTP_CREATE {
        BUSINESSPARTNER(bpParent)
        CONTACTPERSON(bpContact)
        VALIDFROMDATE(sapDateFrom)
        VALIDUNTILDATE(sapDateTo)
    }

    message.setBody(writer.toString());
    message.setHeader("Content-Type", "application/xml");

    return message;
}

def void checkBapiReturn(def xmlResponse) {
    def errorNodes = xmlResponse.RETURN.item.findAll {
        it.TYPE.text() in ["E", "A", "X"]
    }
    if (errorNodes && errorNodes.size() > 0) {
        def errMsg = errorNodes.collect { it.MESSAGE.text() }.join(" | ");
        throw new RuntimeException("Échec de BAPI_BUPA_ROLE_ADD_2 : " + errMsg);
    }
}

def String convertToSapDate(String dateStr, boolean isEndDate) {
    if (!dateStr) {
        return isEndDate ? "99991231" : new SimpleDateFormat("yyyyMMdd").format(new Date());
    }
    try {
        // Enlève les tirets éventuels (ex: '2026-08-06' -> '20260806')
        return dateStr.replaceAll("-", "").trim();
    } catch(Exception e) {
        throw new RuntimeException("Erreur de conversion de date pour '" + dateStr + "' : " + e.getMessage());
    }
}
