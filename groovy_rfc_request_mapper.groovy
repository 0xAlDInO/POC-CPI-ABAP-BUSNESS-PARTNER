import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonBuilder
import groovy.json.JsonSlurper
import groovy.xml.MarkupBuilder

def Message processData(Message message) {
    def input
    try {
        input = new JsonSlurper().parseText(message.getBody(String))
    } catch (Exception e) {
        return error(message, "Le payload JSON est invalide.")
    }

    if (!(input instanceof Map)) return error(message, "Le payload JSON doit être un objet.")

    def mandatory = ["BpParent", "FirstName", "LastName"].findAll { !input[it]?.toString()?.trim() }
    if (mandatory) return error(message, "Champs obligatoires manquants : ${mandatory.join(', ')}")

    def datePattern = ~/\d{4}-\d{2}-\d{2}/
    ["DateFrom", "DateTo"].each { name ->
        if (input[name] && !(input[name].toString() ==~ datePattern)) {
            input.__dateError = "${name} doit être au format YYYY-MM-DD."
        }
    }
    if (input.__dateError) return error(message, input.__dateError)

    def addressFields = ["Street", "HouseNumber", "PostalCode", "City", "Region", "Language"]
    if (addressFields.any { input[it] } && !input.Country) return error(message, "Country est obligatoire lorsqu'une adresse est fournie.")

    input.BpCategory = input.BpCategory ?: "1"
    input.Grouping = input.Grouping ?: "ZC"
    input.BpRole = input.BpRole ?: "BUP001"
    if (input.BpCategory != "1") return error(message, "BpCategory doit être 1 pour un contact personne.")

    def xmlWriter = new StringWriter()
    def xml = new MarkupBuilder(xmlWriter)
    xml.ZRFC_BP_CONTACT_EQ1 {
        IV_BP_PARENT(input.BpParent.toString().padLeft(10, '0'))
        IV_FIRST_NAME(input.FirstName)
        IV_LAST_NAME(input.LastName)
        IV_BP_CATEGORY(input.BpCategory)
        IV_GROUPING(input.Grouping)
        IV_BP_ROLE(input.BpRole)
        IV_STREET(input.Street ?: '')
        IV_HOUSE_NUMBER(input.HouseNumber ?: '')
        IV_POSTAL_CODE(input.PostalCode ?: '')
        IV_CITY(input.City ?: '')
        IV_COUNTRY(input.Country ? input.Country.toString().toUpperCase() : '')
        IV_REGION(input.Region ?: '')
        IV_LANGUAGE(input.Language ?: '')
        IV_DATE_FROM(input.DateFrom ? input.DateFrom.toString().replace('-', '') : '')
        IV_DATE_TO(input.DateTo ? input.DateTo.toString().replace('-', '') : '')
    }

    message.setProperty("original_bp_parent", input.BpParent)
    message.setProperty("original_first_name", input.FirstName)
    message.setProperty("original_last_name", input.LastName)
    message.setProperty("is_integration_failed", "false")
    message.setBody(xmlWriter.toString())
    message.setHeader("Content-Type", "application/xml")
    return message
}

def Message error(Message message, String description) {
    message.setBody(new JsonBuilder([
        BpContactId: "", StatusCode: "ERROR", StatusMessage: description
    ]).toString())
    message.setProperty("is_integration_failed", "true")
    message.setHeader("CamelHttpResponseCode", 400)
    message.setHeader("Content-Type", "application/json")
    return message
}
