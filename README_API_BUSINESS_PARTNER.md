# Alternative standard — `API_BUSINESS_PARTNER` OData

Ce guide décrit une alternative au service custom `ZODATA_BP_CONTACT_EQ1_SRV` : l'API OData standard SAP `API_BUSINESS_PARTNER`.

L'API standard permet de créer un Business Partner, son adresse, son rôle et sa relation de contact. Elle évite le développement SEGW/ABAP custom, mais la création d'un contact lié à un BP parent nécessite plusieurs appels SAP lorsque le numéro du contact est attribué en interne.

> Le flux reste synchrone pour le client si CPI orchestre les appels. En revanche, ce n'est pas un seul appel OData SAP comme le service custom.

## 1. Prérequis

- Le service `/sap/opu/odata/sap/API_BUSINESS_PARTNER` est activé dans `/IWFND/MAINT_SERVICE`.
- L'utilisateur technique possède les autorisations Business Partner nécessaires.
- Le groupement `ZC`, le rôle `BUP001` et la relation `BUR001` sont configurés dans le système.
- Le BP parent existe. Utilisez son numéro interne SAP sur 10 caractères dans les appels standards, par exemple `0005200000` pour le BP affiché `5200000`.
- Pour les requêtes d'écriture, récupérez un jeton CSRF et conservez les cookies de session.

La documentation SAP confirme que `API_BUSINESS_PARTNER` prend en charge les opérations CRUD, les créations `POST` et les deep payloads. [Documentation SAP de l'API](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/44e06f22436c43e582db6ccd5250e29b/85043858ea0f9244e10000000a4450e5.html)

## 2. Headers communs

Utilisez les headers suivants pour tous les `POST` :

```text
Accept: application/json
Content-Type: application/json
X-CSRF-Token: <token-récupéré>
Cookie: <cookies-de-session>
```

Pour récupérer le token :

```text
GET /sap/opu/odata/sap/API_BUSINESS_PARTNER/$metadata
X-CSRF-Token: Fetch
```

Conservez le header `x-csrf-token` reçu et les cookies de la réponse pour les appels suivants.

## 3. Jeu de données de test

Adaptez uniquement le BP parent à un BP réellement existant dans votre système.

| Donnée | Valeur de test |
| --- | --- |
| BP parent existant | `0005200000` |
| Catégorie contact | `1` (Person) |
| Groupement contact | `ZC` |
| Rôle contact | `BUP001` |
| Relation | `BUR001` |
| Prénom / nom | `Jean` / `Dupont API` |
| Adresse | 42 Rue de Rivoli, 75001 Paris, FR |

## 4. Appel 1 — créer le BP Person et son adresse

```text
POST /sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner
```

```json
{
  "BusinessPartnerCategory": "1",
  "BusinessPartnerGrouping": "ZC",
  "FirstName": "Jean",
  "LastName": "Dupont API",
  "to_BusinessPartnerAddress": [
    {
      "Country": "FR",
      "StreetName": "Rue de Rivoli",
      "HouseNumber": "42",
      "PostalCode": "75001",
      "CityName": "Paris",
      "Region": "11",
      "Language": "FR"
    }
  ]
}
```

Résultat attendu : `HTTP 201 Created`. Relevez la propriété `BusinessPartner` de la réponse. Dans les étapes suivantes, elle est notée `<BP_CONTACT_CREE>`.

L'endpoint `A_BusinessPartner` est l'endpoint de création officiel ; SAP documente également la création avec deep payload incluant l'adresse. [Créer des données BP avec deep payload](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/44e06f22436c43e582db6ccd5250e29b/a9ce55233bd6419f84b4af05df9134fa.html)

## 5. Appel 2 — ajouter le rôle de contact

```text
POST /sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartnerRole
```

```json
{
  "BusinessPartner": "<BP_CONTACT_CREE>",
  "BusinessPartnerRole": "BUP001"
}
```

Résultat attendu : `HTTP 201 Created`.

## 6. Appel 3 — rattacher le contact au BP parent

```text
POST /sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartnerContact
```

```json
{
  "BusinessPartnerCompany": "0005200000",
  "BusinessPartnerPerson": "<BP_CONTACT_CREE>",
  "RelationshipCategory": "BUR001",
  "ValidityStartDate": "/Date(1785888000000)/",
  "ValidityEndDate": "/Date(253402300799000)/"
}
```

- `BusinessPartnerCompany` est le BP parent.
- `BusinessPartnerPerson` est l'identifiant retourné par l'appel 1.
- `ValidityStartDate` correspond au 5 août 2026 UTC dans le format OData V2 ; adaptez-la à votre date de test.
- `ValidityEndDate` correspond au 31 décembre 9999 UTC.

Résultat attendu : `HTTP 201 Created`. L'entité standard `A_BusinessPartnerContact` expose notamment le parent, la personne, la catégorie de relation et les dates de validité. [Référence SAP de l'entité Contact](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/44e06f22436c43e582db6ccd5250e29b/bd5e045826552246e10000000a441470.html)

## 7. Vérification finale

```text
GET /sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner('<BP_CONTACT_CREE>')?$expand=to_BusinessPartnerRole,to_BusinessPartnerAddress
```

Vérifiez que le BP est une personne (`BusinessPartnerCategory = 1`), que le rôle `BUP001` est présent, puis consultez `A_BusinessPartnerContact` pour confirmer la relation `BUR001` avec le parent.

## 8. Configuration CPI recommandée

Dans CPI, remplacez le seul appel OData du flux custom par trois **Request Reply** séquentiels :

1. `POST A_BusinessPartner` — crée le contact et récupère `BusinessPartner`.
2. `POST A_BusinessPartnerRole` — ajoute `BUP001`.
3. `POST A_BusinessPartnerContact` — crée la relation `BUR001` vers le parent.

Conservez le même HTTPS Sender et le même Exception Subprocess. Entre les appels, utilisez un script Groovy ou un Content Modifier pour stocker l'identifiant créé dans une propriété, par exemple `bp_contact_created`.

## 9. Limites importantes

- L'API standard ne reproduit pas automatiquement la logique de doublon du service custom (même prénom/nom pour le même parent). Cette recherche doit être ajoutée dans CPI si elle reste nécessaire.
- Trois appels successifs ne fournissent pas le rollback unique implémenté par les BAPIs du service custom. Pour une atomicité renforcée, étudiez un `$batch` OData avec changeset et testez-le dans votre version S/4HANA.
- Avant intégration, vérifiez les propriétés exactes de votre release via :

  ```text
  GET /sap/opu/odata/sap/API_BUSINESS_PARTNER/$metadata
  ```
