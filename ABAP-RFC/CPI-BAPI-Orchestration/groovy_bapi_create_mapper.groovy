import com.sap.gateway.ip.core.customdev.util.Message;
import groovy.json.JsonSlurper;
import groovy.xml.MarkupBuilder;

def Message processData(Message message) {
    def body = message.getBody(java.lang.String);
    def jsonSlurper = new JsonSlurper();
    def inputMap = [:];

    try {
        inputMap = jsonSlurper.parseText(body);
    } catch(Exception e) {
        throw new RuntimeException("Format de payload JSON invalide : " + e.getMessage());
    }

    // Validation des champs obligatoires
    def missingFields = [];
    if (!inputMap.BpParent) missingFields.add("BpParent");
    if (!inputMap.FirstName) missingFields.add("FirstName");
    if (!inputMap.LastName) missingFields.add("LastName");

    if (missingFields.size() > 0) {
        throw new RuntimeException("Champs obligatoires manquants pour la création du BP : " + missingFields.join(", "));
    }

    // Extraction et normalisation des valeurs
    def bpCategory = inputMap.BpCategory ?: "1";
    def grouping   = inputMap.Grouping ?: "ZC";
    def bpRole     = inputMap.BpRole ?: "BUP001";
    def language   = (inputMap.Language ?: "F").toUpperCase();

    // Enregistrement des propriétés d'échange Camel pour les étapes suivantes
    message.setProperty("bapi_prop_bp_parent", inputMap.BpParent);
    message.setProperty("bapi_prop_bp_role", bpRole);
    message.setProperty("bapi_prop_first_name", inputMap.FirstName);
    message.setProperty("bapi_prop_last_name", inputMap.LastName);
    message.setProperty("bapi_prop_date_from", inputMap.DateFrom ?: "");
    message.setProperty("bapi_prop_date_to", inputMap.DateTo ?: "");

    // Construction du XML RFC pour BAPI_BUPA_CREATE_FROM_DATA
    def writer = new StringWriter();
    def xml = new MarkupBuilder(writer);

    xml.BAPI_BUPA_CREATE_FROM_DATA {
        PARTNERCATEGORY(bpCategory)
        PARTNERGROUP(grouping)

        CENTRALDATA {
            // Pas de données d'en-tête centrales complexes requises
        }

        CENTRALDATAPERSON {
            FIRSTNAME(inputMap.FirstName)
            LASTNAME(inputMap.LastName)
            CORRESPONDLANGUAGE(language)
        }

        ADDRESSDATA {
            STREET(inputMap.Street ?: "")
            HOUSE_NO(inputMap.HouseNumber ?: "")
            POSTL_COD1(inputMap.PostalCode ?: "")
            CITY(inputMap.City ?: "")
            COUNTRY((inputMap.Country ?: "").toUpperCase())
            REGION(inputMap.Region ?: "")
        }
    }

    message.setBody(writer.toString());
    message.setHeader("Content-Type", "application/xml");

    return message;
}
