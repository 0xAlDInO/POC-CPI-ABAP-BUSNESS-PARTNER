# Gestion du Statut HTTP 201 (Created) au lieu de 200 dans SAP CPI

Lors de l'appel d'un iFlow CPI d'intégration RFC (que ce soit pour la version procédurale ou pour la version Orientée Objet Globale), il peut arriver que l'iFlow retourne par défaut un code **`HTTP 200 OK`** au lieu d'un code **`HTTP 201 Created`** lors d'une création réussie de Business Partner dans SAP.

Ce guide explique pourquoi ce comportement survient et détaille la démarche de configuration, les composants nécessaires et le code du script Groovy pour garantir le retour d'un statut **`201`**.

---

## 1. Pourquoi CPI retourne-t-il un code HTTP 200 ?

Par défaut, l'adaptateur **HTTPS Sender** de SAP CPI, après traitement réussi du flux synchrone (Request-Reply), applique un statut HTTP générique **`200 OK`** si aucun code de statut HTTP explicite n'a été positionné dans les en-têtes du message Camel d'échange.

Pour retourner un code spécifique comme **`201 Created`** lors d'une création réussie de Business Partner (ou d'autres codes d'erreur comme `409 Conflict`, `423 Locked`, etc.), il est impératif d'utiliser un composant **Groovy Script** sur le chemin de retour afin de modifier programmatiquement les en-têtes HTTP de la réponse.

---

## 2. Démarche et Composants iFlow nécessaires

Pour mettre en place cette gestion de statut professionnelle :

1. **Placer un script Groovy de traitement de réponse :**
   Insérez un composant **Groovy Script** juste après votre appel RFC (Request Reply adaptateur RFC) et avant l'événement de fin nominal (**End Message**).
2. **Utiliser l'en-tête Camel `CamelHttpResponseCode` :**
   C'est cet en-tête d'échange spécifique qui est lu par l'adaptateur HTTPS Sender pour définir le code de réponse HTTP renvoyé au client.
3. **Mapper dynamiquement selon le code statut retourné par SAP :**
   Le script Groovy parse le flux XML de retour du RFC SAP (qui contient l'export `EV_STATUS_CODE`) et affecte le statut HTTP correspondant.

---

## 3. Le Script Groovy de Traitement de Réponse (`groovy_rfc_response_handler.groovy` dans `ABAP-RFC/CPI-RFC/`)

Voici le script Groovy recommandé pour votre iFlow. Il extrait l'identifiant du contact créé, parse l'export de statut RFC (`EV_STATUS_CODE`), puis configure l'en-tête `CamelHttpResponseCode` :

```groovy
import com.sap.gateway.ip.core.customdev.util.Message
import groovy.json.JsonBuilder

def Message processData(Message message) {
    // 1. Parsing du flux XML de retour envoyé par l'adaptateur RFC SAP
    def xml = new XmlSlurper(false, false).parseText(message.getBody(String))

    // Fonction utilitaire pour extraire la valeur d'un nœud XML
    def value = { String field ->
        def node = xml.'**'.find { it.name().toString().tokenize(':').last() == field }
        node ? node.text() : ""
    }

    // Extraction des paramètres d'export RFC
    def status = value("EV_STATUS_CODE")
    def contact = value("EV_BP_CONTACT")
    def description = value("EV_STATUS_MESSAGE")

    // Validation de la présence d'un statut connu
    if (!(status in ["SUCCESS", "EXISTS", "LOCKED", "ERROR"])) {
        throw new IllegalStateException("Réponse RFC invalide : EV_STATUS_CODE absent ou inconnu.")
    }

    // 2. Détermination dynamique du Code Statut HTTP
    // Si 'SUCCESS' -> HTTP 201 (Created)
    // Si 'EXISTS'  -> HTTP 409 (Conflict)
    // Si 'LOCKED'  -> HTTP 423 (Locked)
    // Si 'ERROR'   -> HTTP 400 (Bad Request)
    def httpStatus = status == "SUCCESS" ? 201 :
        (status == "EXISTS" ? 409 : (status == "LOCKED" ? 423 : 400))

    // 3. Construction du payload de réponse JSON propre
    message.setBody(new JsonBuilder([
        BpParent: message.getProperty("original_bp_parent") ?: "",
        FirstName: message.getProperty("original_first_name") ?: "",
        LastName: message.getProperty("original_last_name") ?: "",
        BpContactId: contact,
        StatusCode: status,
        StatusMessage: description
    ]).toString())

    // 4. Affectation des en-têtes HTTP de sortie
    message.setHeader("Content-Type", "application/json")
    message.setHeader("CamelHttpResponseCode", httpStatus) // Assure le retour 201 Created pour SUCCESS

    return message;
}
```

---

## 4. Points de Contrôle essentiels dans l'iFlow CPI

Afin que le header `CamelHttpResponseCode` soit propagé correctement au client externe :

- **Pas d'écrasement ultérieur :** Assurez-vous qu'aucun composant de type *Content Modifier* placé après le script Groovy ne réinitialise ou ne supprime les en-têtes de message.
- **Exceptions Techniques :** Pour les pannes réseau ou d'autorisation (qui lèvent des exceptions Java et n'atteignent pas le script nominal), utilisez l'**`Exception Subprocess`** avec un script d'erreur dédié positionnant le code `502` ou `500` via le même en-tête :
  ```groovy
  message.setHeader("CamelHttpResponseCode", 502)
  ```
- **Préservation des en-têtes dans l'HTTPS Sender :** Dans les paramètres de l'adaptateur HTTPS d'entrée (Sender), l'option par défaut propage tous les en-têtes Camel. Aucune configuration restrictive supplémentaire n'est requise.
