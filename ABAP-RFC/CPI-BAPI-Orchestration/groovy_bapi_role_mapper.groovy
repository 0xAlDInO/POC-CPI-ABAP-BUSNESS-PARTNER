import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.xml.MarkupBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def xmlResponse = new XmlSlurper(false, false).parseText(body);

    // Extraction des retours BAPI de l'étape 1
    checkBapiReturn(xmlResponse);

    // Extraction du numéro de Business Partner créé par SAP
    def bpContactCreated = xmlResponse.BUSINESSPARTNER?.text()?.trim();
    if (!bpContactCreated) {
        throw new RuntimeException("Aucun numéro de contact (BUSINESSPARTNER) n'a été retourné par BAPI_BUPA_CREATE_FROM_DATA.");
    }

    // Sauvegarde de l'ID de contact créé dans les propriétés d'échange CPI
    message.setProperty("bapi_prop_bp_contact_created", bpContactCreated);

    // Récupération du rôle mémorisé
    def bpRole = message.getProperty("bapi_prop_bp_role");

    // Construction du XML RFC pour BAPI_BUPA_ROLE_ADD_2
    def writer = new StringWriter();
    def xml = new MarkupBuilder(writer);

    xml.BAPI_BUPA_ROLE_ADD_2 {
        BUSINESSPARTNER(bpContactCreated)
        BUSINESSPARTNERROLE(bpRole)
    }

    message.setBody(writer.toString());
    message.setHeader("Content-Type", "application/xml");

    return message;
}

def void checkBapiReturn(def xmlResponse) {
    // On recherche d'éventuelles erreurs (Type E, A, X) dans la table RETURN du BAPI
    def errorNodes = xmlResponse.RETURN.item.findAll {
        it.TYPE.text() in ["E", "A", "X"]
    }
    if (errorNodes && errorNodes.size() > 0) {
        def errMsg = errorNodes.collect { it.MESSAGE.text() }.join(" | ");
        throw new RuntimeException("Échec de BAPI_BUPA_CREATE_FROM_DATA : " + errMsg);
    }
}
