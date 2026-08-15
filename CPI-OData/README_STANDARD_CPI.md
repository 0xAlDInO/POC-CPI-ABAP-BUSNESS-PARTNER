# Intégration et Orchestration OData Standard via SAP CPI

Ce guide décrit comment intégrer et orchestrer les trois processus de création et d'association de Business Partner en utilisant l'API OData standard **`API_BUSINESS_PARTNER`** dans un unique artefact SAP CPI (iFlow).

Le client externe envoie l'intégralité du payload via un unique appel HTTP (par exemple, depuis Postman). C'est ensuite à l'iFlow SAP CPI d'exécuter séquentiellement et de manière synchrone les trois étapes requisés dans SAP, en récupérant dynamiquement l'ID généré par l'étape précédente.

---

## 1. Vue d'Ensemble de l'Orchestration CPI

L'iFlow s'articule autour de la séquence suivante :

```text
  [ Client Postman (Payload Unique JSON) ]
                      │
                      ▼ (HTTPS Sender: /v1/sap/contacts-standard)
  ┌───────────────────────────────────────────────────────────┐
  │ 1. Script Groovy : Validation & Payload BusinessPartner   │ [groovy_standard_bp_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (POST A_BusinessPartner)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 2. Request Reply : Création du Business Partner Person    │ (Génère l'ID Contact)
  └───────────────────────────┬───────────────────────────────┘
                              │ (Réponse OData JSON)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 3. Script Groovy : Extraction de l'ID & Payload Rôle      │ [groovy_standard_role_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (POST A_BusinessPartnerRole)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 4. Request Reply : Affectation du Rôle de Contact (BUP001)│
  └───────────────────────────┬───────────────────────────────┘
                              │ (Réponse OData JSON)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 5. Script Groovy : Payload Relation & Date OData          │ [groovy_standard_relation_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (POST A_BusinessPartnerContact)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 6. Request Reply : Liaison de contact avec le BP Parent   │ (Lien BUR001)
  └───────────────────────────┬───────────────────────────────┘
                              │ (Réponse OData JSON)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 7. Script Groovy : Mise en forme de la réponse de succès  │ [groovy_standard_response_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (HTTP 201 Created)
                              ▼
           [ Réponse JSON Unique renvoyée au Client ]
```

---

## 2. Scripts Groovy Utilisés pour l'iFlow

Les scripts Groovy suivants doivent être importés dans l'onglet **Resources** de votre iFlow CPI :

1. **`groovy_standard_bp_mapper.groovy`** :
   - Valide les données reçues de Postman (`BpParent`, `FirstName`, `LastName`).
   - Mémorise les données d'origine dans des propriétés d'échange CPI (`prop_bp_parent`, `prop_bp_role`, `prop_first_name`, `prop_last_name`, `prop_date_from`, `prop_date_to`).
   - Génère le payload d'adresse imbriquée (`to_BusinessPartnerAddress`) et l'entité de création de base `A_BusinessPartner`.
2. **`groovy_standard_role_mapper.groovy`** :
   - Extrait la propriété `d.BusinessPartner` (l'identifiant créé par SAP) de la réponse du premier appel.
   - Le stocke dans la propriété d'échange `prop_bp_contact_created`.
   - Construit le payload JSON pour l'association du rôle (`A_BusinessPartnerRole`).
3. **`groovy_standard_relation_mapper.groovy`** :
   - Récupère l'ID du contact créé et celui du parent.
   - Convertit les dates reçues au format d'époque OData V2 requis par SAP (par exemple `/Date(1785888000000)/`).
   - Construit le payload JSON pour l'entité `A_BusinessPartnerContact`.
4. **`groovy_standard_response_mapper.groovy`** :
   - Construit la réponse JSON finale unifiée pour le client (Postman) contenant l'ID créé par SAP, le BP Parent, et le statut `SUCCESS`.
5. **`groovy_standard_error_handler.groovy`** :
   - Intercepte toute exception survenue durant les étapes ou les appels OData SAP (au sein d'un *Exception Subprocess*).
   - Formate un payload d'erreur unifié et renvoie un code HTTP `502 Bad Gateway`.

---

## 3. Configuration des Adaptateurs OData V2 Receivers

Chaque **Request Reply** est configuré avec un adaptateur **OData V2** ou **HTTP** pointant vers l'API standard `API_BUSINESS_PARTNER` de SAP S/4HANA.

### Configuration Générale de l'Adaptateur
- **Address** : `https://<sap-host>:<port>/sap/opu/odata/sap/API_BUSINESS_PARTNER`
- **Proxy Type** : `On-Premise` (via SAP Cloud Connector)
- **Credential Name** : Vos identifiants de connexion enregistrés dans le Security Material.
- **CSRF Token Handling** : Choisissez **`Fetch`** (obligatoire pour autoriser les écritures `POST` de manière sécurisée).

### Chemins d'accès aux ressources
1. **Étape 1 (Business Partner)** :
   - **Resource Path** : `A_BusinessPartner`
   - **Operation** : `CREATE`
   - **Content Type & Accept** : `application/json`
2. **Étape 2 (Rôle)** :
   - **Resource Path** : `A_BusinessPartnerRole`
   - **Operation** : `CREATE`
   - **Content Type & Accept** : `application/json`
3. **Étape 3 (Relation)** :
   - **Resource Path** : `A_BusinessPartnerContact`
   - **Operation** : `CREATE`
   - **Content Type & Accept** : `application/json`

---

## 4. Format Unique de Payload (Postman)

Pour tester ce flux, configurez une requête `POST` dans Postman pointant vers l'endpoint HTTPS CPI `/http/v1/sap/contacts-standard` avec le corps JSON suivant :

```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont OData",
  "BpCategory": "1",
  "Grouping": "ZC",
  "BpRole": "BUP001",
  "Street": "Rue de Rivoli",
  "HouseNumber": "42",
  "PostalCode": "75001",
  "City": "Paris",
  "Country": "FR",
  "Region": "11",
  "Language": "FR",
  "DateFrom": "2026-08-05",
  "DateTo": "9999-12-31"
}
```

---

## 5. Format de Réponse de Succès Unique Renvoyée

Si les trois étapes réussissent, CPI retourne un code **`201 Created`** avec le JSON unifié suivant :

```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont OData",
  "BpContactId": "0005300999",
  "StatusCode": "SUCCESS",
  "StatusMessage": "Le contact a été créé avec succès, s'est vu affecter son rôle et a été rattaché au BP Parent 0005200000."
}
```

---

## 6. Traitement des Exceptions et Gestion Transactionnelle

- **Exception Subprocess** : Si SAP S/4HANA retourne une erreur HTTP (ex: `400 Bad Request` ou `500 Internal Error`) lors de l'une des trois étapes, l'exécution s'interrompt et le contrôle est transmis à l'**`Exception Subprocess`**.
- Le script `groovy_standard_error_handler.groovy` extrait le message d'erreur d'origine retourné par SAP, et le renvoie de manière propre au client externe avec un code `502`.
