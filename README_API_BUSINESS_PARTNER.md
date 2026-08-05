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

## 3. Normes d'intégration à respecter

Ces règles sont importantes car le numéro attribué par SAP lors de l'appel 1 est la dépendance des appels 2 et 3.

| Règle | Application dans cet iFlow |
| --- | --- |
| **Exécution strictement séquentielle** | Ne pas utiliser de Multicast ni de Splitter : l'appel 2 ne démarre qu'après un `201` de l'appel 1, et l'appel 3 qu'après un `201` de l'appel 2. |
| **Numéro BP traité comme texte** | Conserver `BusinessPartner` exactement tel que SAP le retourne, y compris les zéros à gauche (`0005200001`). Ne jamais le convertir en nombre. |
| **Contrôle de réponse** | Après chaque Request Reply, vérifier le code HTTP et l'existence du champ attendu. Si l'appel 1 ne retourne pas `d.BusinessPartner`, arrêter le flux. |
| **CSRF et session** | L'adaptateur OData doit gérer le token CSRF et la session pour les trois `POST`. Ne transmettez jamais un token codé en dur dans un script. |
| **Secrets hors du code** | Utiliser le Security Material CPI (User Credentials ou OAuth2) ; ne mettre ni mot de passe, ni URL interne, ni identifiant SAP dans les scripts ou le dépôt. |
| **Idempotence** | Transmettre un `X-Correlation-ID` généré ou fourni par le client et le journaliser. Une reprise automatique après l'appel 1 peut sinon créer un second contact. |
| **Données personnelles** | Ne pas tracer le payload complet en production. Masquer au minimum nom, prénom et adresse dans les logs CPI. |
| **Dates** | Construire les dates OData V2 à partir d'une date ISO validée, en UTC. Ne pas coder en dur un timestamp dans le script. |
| **Référentiel SAP** | Valider en customizing que `ZC`, `BUP001` et `BUR001` sont autorisés pour le scénario avant le déploiement. |

Le contrat recommandé vers le client est : `201` lorsque les trois opérations ont réussi, `400` pour une entrée invalide, `404` si le parent n'existe pas, `409` en cas de doublon métier, et `502/500` pour une erreur SAP/CPI. Le corps peut conserver votre champ `StatusCode`, mais il ne doit pas contredire le statut HTTP.

## 4. Jeu de données de test

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

## 5. Appel 1 — créer le BP Person et son adresse

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

## 6. Appel 2 — ajouter le rôle de contact

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

## 7. Appel 3 — rattacher le contact au BP parent

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

## 8. Vérification finale

```text
GET /sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner('<BP_CONTACT_CREE>')?$expand=to_BusinessPartnerRole,to_BusinessPartnerAddress
```

Vérifiez que le BP est une personne (`BusinessPartnerCategory = 1`), que le rôle `BUP001` est présent, puis consultez `A_BusinessPartnerContact` pour confirmer la relation `BUR001` avec le parent.

## 9. iFlow CPI — composants nécessaires

Créez un iFlow synchrone distinct pour l'API standard. Il reçoit une seule requête du client, puis CPI exécute les trois appels SAP dans l'ordre.

```text
HTTPS Sender
  → Groovy 1 : validation + normalisation du BP parent
  → Router (payload invalide → End Message HTTP 400)
  → Request Reply 0 (recommandé) → OData V2 Receiver : lecture du BP parent
  → Request Reply 1 → OData V2 Receiver 1 : A_BusinessPartner
  → Groovy 2 : contrôle réponse 1, extrait BusinessPartner + payload rôle
  → Request Reply 2 → OData V2 Receiver 2 : A_BusinessPartnerRole
  → Groovy 3 : contrôle réponse 2 + payload relation
  → Request Reply 3 → OData V2 Receiver 3 : A_BusinessPartnerContact
  → Groovy : réponse finale uniforme
  → End Message

Exception Subprocess
  → Groovy : erreur technique → End Message HTTP 500
```

| Composant CPI | Quantité | Utilisation |
| --- | ---: | --- |
| HTTPS Sender + Start Event | 1 | Reçoit le `POST` du client. |
| Groovy Script | 4 | Validation/mapping BP, contrôle+mapping rôle, contrôle+mapping relation, réponse finale. |
| Router | 1 | Arrête immédiatement un payload invalide avec HTTP 400. |
| Request Reply | 3 minimum, 4 recommandé | Les trois `POST` séquentiels ; ajoutez un `GET` préalable pour vérifier le parent. |
| OData V2 Receiver | 3 minimum, 4 recommandé | Un adaptateur par ressource standard ; le quatrième lit le parent. |
| End Message | 2 | Réponse nominale et réponse HTTP 400. |
| Exception Subprocess | 1 | Capture les exceptions techniques. |
| Groovy Script dans l'exception | 1 | Construit la réponse `HTTP 500 / StatusCode ERROR`. |
| End Message dans l'exception | 1 | Termine le sous-processus d'exception. |

Les trois **Request Reply** sont indispensables : ils conservent le même message CPI et permettent au script suivant de remplacer le body tout en gardant le numéro SAP dans une propriété. Un **Content Modifier** peut remplacer un script seulement pour des valeurs fixes ; il ne suffit pas pour extraire le numéro BP de la réponse 1.

## 10. iFlow CPI — configuration pas à pas

### Étape 1 — HTTPS Sender

1. Créez l'iFlow dans un package CPI.
2. Ajoutez un **HTTPS Sender** sur le Start Event, par exemple avec l'adresse :

   ```text
   /v1/sap/contacts-standard
   ```

3. Ajoutez ensuite le premier script Groovy.

### Étape 2 — validation et création du payload BP

Le premier script doit :

- valider au minimum `BpParent`, `FirstName` et `LastName` ;
- poser les défauts `BpCategory: 1`, `Grouping: ZC`, `BpRole: BUP001` ;
- créer le body de l'appel 1 (`A_BusinessPartner`) conformément au JSON de la section 5 ;
- mémoriser `BpParent`, `BpRole` et les données initiales dans des propriétés CPI ;
- générer ou reprendre `correlation_id`, puis le mettre dans le header `X-Correlation-ID` ;
- poser `is_integration_failed = true` et `CamelHttpResponseCode = 400` en cas de payload invalide.

Ajoutez un **Router** après ce script :

- branche erreur : `${property.is_integration_failed} = 'true'` → **End Message** ;
- **Default Route** : poursuit vers le premier Request Reply.

Avant la création, ajoutez de préférence un **Request Reply 0** qui appelle `GET A_BusinessPartner('<BpParent>')`. S'il retourne `404`, renvoyez immédiatement `404` au client. Ce contrôle évite de créer un BP contact qui ne pourra pas être rattaché parce que le parent est absent.

### Étape 3 — Request Reply 1 : créer le BP

1. Ajoutez un **Request Reply** sur la Default Route.
2. Reliez-le à un premier **OData V2 Receiver**.
3. Paramétrez l'adaptateur :

   | Paramètre | Valeur |
   | --- | --- |
   | Address | `https://<virtual-host>:<port>/sap/opu/odata/sap/API_BUSINESS_PARTNER` |
   | Proxy Type | `On-Premise` |
   | Resource Path | `A_BusinessPartner` |
   | Operation | `CREATE` |
   | Format requête/réponse | JSON |

4. Configurez l'authentification avec un artefact **Security Material** CPI et activez la gestion CSRF/cookies de l'adaptateur selon les options de votre tenant. Si cette gestion n'est pas disponible pour votre configuration, ajoutez avant le premier POST un Request Reply HTTP qui récupère le token et les cookies ; ne les stockez pas en dur.
5. Demandez une réponse avec représentation de l'entité créée (ne pas utiliser `Prefer: return=minimal`) : le script suivant a impérativement besoin de `d.BusinessPartner`.
6. Conservez la réponse uniquement si elle est un succès HTTP et contient `d.BusinessPartner`. Le script suivant doit sinon lever une exception afin d'entrer dans l'Exception Subprocess.

### Étape 4 — extraire l'identifiant et ajouter le rôle

Après le premier Request Reply, ajoutez un deuxième script Groovy. Il doit :

1. Lire `d.BusinessPartner` dans la réponse OData V2 et vérifier qu'il n'est pas vide.
2. Le stocker, sans transformation, dans la propriété CPI `bp_contact_created`.
3. Remplacer le body par :

   ```json
   {
     "BusinessPartner": "<bp_contact_created>",
     "BusinessPartnerRole": "BUP001"
   }
   ```

4. Ajoutez le second **Request Reply** et un second **OData V2 Receiver**, avec `Resource Path = A_BusinessPartnerRole` et `Operation = CREATE`.

### Étape 5 — créer la relation de contact

Après le second Request Reply, ajoutez un troisième script Groovy. Il vérifie que l'ajout de rôle a réussi, puis construit le body suivant avec les propriétés CPI mémorisées :

```json
{
  "BusinessPartnerCompany": "<BpParent sur 10 caractères>",
  "BusinessPartnerPerson": "<bp_contact_created>",
  "RelationshipCategory": "BUR001",
  "ValidityStartDate": "/Date(<timestamp>)/",
  "ValidityEndDate": "/Date(253402300799000)/"
}
```

Ajoutez le troisième **Request Reply** et le troisième **OData V2 Receiver**, avec `Resource Path = A_BusinessPartnerContact` et `Operation = CREATE`.

### Étape 6 — réponse et exceptions

1. Ajoutez un dernier script Groovy après le troisième Request Reply. Vérifiez que la relation retournée contient le parent, la personne et `BUR001`, puis retournez le BP créé, le parent, `SUCCESS` et le message fonctionnel.
2. Terminez le chemin nominal par un **End Message** avec HTTP 201.
3. Ajoutez un **Exception Subprocess** non relié au chemin nominal :
   - Groovy Script d'erreur ;
   - End Message avec HTTP 500.

### Étape 7 — déployer et tester

1. Déployez l'iFlow.
2. Envoyez le payload client vers :

   ```text
   POST https://<tenant-cpi>/http/v1/sap/contacts-standard
   ```

3. Vérifiez dans le monitor CPI les trois appels successifs : création du BP, ajout du rôle, création de la relation. Le même `X-Correlation-ID` doit être visible sur le message de bout en bout.

## 11. Tests Postman

Effectuez d'abord le test direct SAP, puis le test de l'iFlow. Cela isole un problème de customizing/API SAP d'un problème CPI.

### A. Test direct de l'API SAP

1. Créez un environnement Postman avec `sapBaseUrl`, `sapUser`, `sapPassword`, `bpParent` et `bpContact`.
2. Envoyez `GET {{sapBaseUrl}}/sap/opu/odata/sap/API_BUSINESS_PARTNER/$metadata` avec `X-CSRF-Token: Fetch`. Postman doit conserver les cookies ; copiez le token dans la variable `csrfToken` si nécessaire.
3. Exécutez les trois `POST` des sections 5, 6 et 7, dans cet ordre. Ajoutez aux trois requêtes les headers communs de la section 2.
4. Dans l'onglet **Tests** de la requête de création, conservez le numéro généré :

   ```javascript
   pm.test("BP créé", () => pm.response.to.have.status(201));
   const response = pm.response.json();
   pm.environment.set("bpContact", response.d.BusinessPartner);
   ```

5. Dans les deux requêtes suivantes, utilisez `{{bpContact}}`. Vérifiez `201`, puis faites le `GET` de la section 8.

### B. Test de l'iFlow CPI

1. Créez une seule requête `POST` vers `https://<tenant-cpi>/http/v1/sap/contacts-standard` avec l'authentification configurée sur le HTTPS Sender.
2. Ajoutez `Content-Type: application/json` et un `X-Correlation-ID` unique.
3. Envoyez le payload métier ci-dessous. Il ne contient pas de token CSRF : CPI le gère côté SAP.

   ```json
   {
     "BpParent": "0005200000",
     "BpCategory": "1",
     "Grouping": "ZC",
     "BpRole": "BUP001",
     "FirstName": "Jean",
     "LastName": "Dupont API",
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

4. Résultat attendu : `201 Created`, avec le BP généré dans `BpContactId` (ou `BusinessPartner`, selon le contrat que vous retenez). Vérifiez dans CPI que les trois appels ont bien été exécutés dans l'ordre.

Tests minimaux à ajouter : parent inexistant (`404`), champ obligatoire absent (`400`), rôle non autorisé (`400`), erreur simulée à l'appel 2, erreur simulée à l'appel 3, et reprise d'une même demande avec la même clé d'idempotence.

## 12. Limites importantes

- L'API standard ne reproduit pas automatiquement la logique de doublon du service custom (même prénom/nom pour le même parent). Cette recherche doit être ajoutée dans CPI si elle reste nécessaire.
- Trois appels successifs ne fournissent pas le rollback unique implémenté par les BAPIs du service custom. Pour une atomicité renforcée, étudiez un `$batch` OData avec changeset et testez-le dans votre version S/4HANA.
- Avant intégration, vérifiez les propriétés exactes de votre release via :

  ```text
  GET /sap/opu/odata/sap/API_BUSINESS_PARTNER/$metadata
  ```
