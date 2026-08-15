import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.xml.MarkupBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def xmlResponse = new XmlSlurper(false, false).parseText(body);

    // Extraction et contrôle des retours de l'étape 3 (Relation de contact)
    checkBapiReturn(xmlResponse);

    // Construction du XML RFC pour BAPI_TRANSACTION_COMMIT
    def writer = new StringWriter();
    def xml = new MarkupBuilder(writer);

    xml.BAPI_TRANSACTION_COMMIT {
        WAIT("X") // Demande d'un commit synchrone avec attente de validation
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
        throw new RuntimeException("Échec de BAPI_BUPR_CONTP_CREATE : " + errMsg);
    }
}
