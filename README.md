# POC - Guide d'Intégration d'Interface Contacts (MDM/Postman ↔ CPI ↔ SAP S/4HANA via OData & BAPI)

Ce guide complet détaille, **étape par étape**, la conception, le paramétrage, l'implémentation et le test de l'interface de création de Contacts (Business Partner de type Personne) rattachés à un Business Partner Parent (Client ou Fournisseur).

Ce projet s'inscrit dans le cadre du Proof of Concept (POC) d'intégration synchrone, simulant des appels depuis Postman (en remplacement de Boomi/Apollo MDM) vers SAP CPI (Cloud Integration), puis vers SAP S/4HANA à l'aide d'un service OData Gateway personnalisé appelant des BAPIs standards.

---

## Sommaire
1. [Vue d'Ensemble & Architecture Globale](#1-vue-densemble--architecture-globale)
2. [Étape 1 : Paramétrage Prérequis dans SAP S/4HANA (Customizing)](#étape-1--paramétrage-prérequis-dans-sap-s4hana-customizing)
3. [Étape 2 : Création de l'OData Service personnalisée (Gateway SEGW)](#étape-2--création-de-lodata-service-personnalisée-gateway-segw)
4. [Étape 3 : Implémentation du Code ABAP de Création (BAPIs & Logique Métier)](#étape-3--implémentation-du-code-abap-de-création-bapis--logique-métier)
5. [Étape 4 : Configuration du SAP Cloud Connector](#étape-4--configuration-du-sap-cloud-connector)
6. [Étape 5 : Conception et Développement de l'iFlow SAP CPI](#étape-5--conception-et-développement-de-liflow-sap-cpi)
7. [Étape 6 : Tests Unitaires et Validation de bout en bout avec Postman](#étape-6--tests-unitaire-et-validation-de-bout-en-bout-avec-postman)
8. [Gestion des Erreurs & Monitoring](#gestion-des-erreurs--monitoring)

---

## 1. Vue d'Ensemble & Architecture Globale

Le flux d'intégration synchrone est orchestré de la manière suivante :
1. **Postman (Émetteur)** : Envoie un unique payload HTTP POST contenant l'ensemble des données du contact et l'identifiant du BP Parent.
2. **SAP CPI (Middleware)** :
   - Intercepte la requête HTTP.
   - Exécute un script **Groovy** de validation technique et d'enrichissement.
   - Réalise l'appel OData vers SAP Gateway en passant par le **Cloud Connector**.
   - En cas d'erreur de communication ou d'échec SAP, un script **Groovy d'Error Handling** formate proprement une réponse JSON uniforme.
3. **SAP S/4HANA (Récepteur/Calcul)** :
   - Le service OData Gateway personnalisé (`/SAP/OPU/ODATA/SAP/ZCONTACTS_SRV`) reçoit la requête.
   - La méthode de création (`CONTACTSET_CREATE_ENTITY`) est appelée :
     - Elle vérifie l'existence du BP Parent.
     - Elle recherche les éventuels doublons (même Nom/Prénom lié au même BP Parent) pour éviter l'encombrement des tables SAP.
     - Elle appelle séquentiellement les BAPIs standards de création de BP, d'assignation de rôles et de création de relations.
     - Elle réalise un `COMMIT` ou un `ROLLBACK` transactionnel strict et renvoie le statut complet au format JSON en un seul échange synchrone.

```
+------------------+         +------------------+         +---------------------+         +---------------------+
|  Client HTTP     |  POST   |  SAP Cloud       |  HTTPS  | SAP Cloud Connector |  HTTPS  |  SAP S/4HANA        |
|  (Postman/Boomi) | ------> |  Integration     | ------> | (Connexion Sécurisée| ------> |  (Gateway OData     |
|                  | <------ |  (iFlow CPI)     | <------ |  On-Premise)        | <------ |   ZCONTACTS_SRV)    |
+------------------+  JSON   +------------------+  OData  +---------------------+  OData  +---------------------+
```

---

### Propriétés de l'entité OData `Contact`

> Dans SEGW, renseignez le **type Edm** et la **longueur maximale** ci-dessous ; les éléments de donnée SAP sont donnés uniquement comme référence.

| Nom de la Propriété (OData) | Type OData | Longueur maximale | Élément de Donnée SAP (référence) | Rôle / Description | Clé | Obligatoire |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `BpParent` | `Edm.String` | 10 | `BU_PARTNER` | Numéro du BP Parent (Organisation / Client / Fournisseur) | Non | Oui |
| `BpCategory` | `Edm.String` | 1 | `BU_TYPE` | Catégorie du BP (BUT000-TYPE) ; valeur par défaut `1` (Person) | Non | Non (défaut : `1`) |
| `Grouping` | `Edm.String` | 4 | `BU_GROUP` | Groupement du BP (TB001-BU_GROUP) ; valeur par défaut `ZC` | Non | Non (défaut : `ZC`) |
| `BpRole` | `Edm.String` | 6 | `BU_PARTNERROLE` | Rôle du BP (BUT100-RLTYP) ; valeur par défaut `BUP001` (Contact Person) | Non | Non (défaut : `BUP001`) |
| `FirstName` | `Edm.String` | 40 | `BU_NAME_FIRST` | Prénom du contact (BUT000-NAME_FIRST) | Non | Oui |
| `LastName` | `Edm.String` | 40 | `BU_NAME_LAST` | Nom de famille du contact (BUT000-NAME_LAST) | Non | Oui |
| `Street` | `Edm.String` | 60 | `AD_STREET` | Nom de la rue (ADRC-STREET) | Non | Non |
| `HouseNumber` | `Edm.String` | 10 | `AD_HSNM1` | Numéro de rue / maison (ADRC-HOUSE_NUM1) | Non | Non |
| `PostalCode` | `Edm.String` | 10 | `AD_PSTCD1` | Code postal (ADRC-POST_CODE1) | Non | Non |
| `City` | `Edm.String` | 40 | `AD_CITY1` | Ville (ADRC-CITY1) | Non | Non |
| `Country` | `Edm.String` | 3 | `LAND1` | Code pays SAP (ADRC-COUNTRY) | Non | Oui (si adresse présente) |
| `Region` | `Edm.String` | 3 | `REGIO` | Code de la région (ADRC-REGION) | Non | Non |
| `Language` | `Edm.String` | 1 | `SPRAS` | Langue de communication (ADRC-LANGU) | Non | Non |
| `DateFrom` | `Edm.DateTime`| 8 SAP / 19 JSON ISO | `BU_DATFROM` | Date de début de validité de la relation (BUT050-DATE_FROM) | Non | Non |
| `DateTo` | `Edm.DateTime`| 8 SAP / 19 JSON ISO | `BU_DATTO` | Date de fin de validité de la relation (BUT050-DATE_TO) | Non | Non |
| `BpContactId` | `Edm.String` | 10 | `BU_PARTNER` | **Généré par SAP** : Numéro interne du nouveau Contact créé | **Oui**| Non |
| `StatusCode` | `Edm.String` | 10 | `CHAR10` | Statut du traitement (`SUCCESS` / `ERROR` / `EXISTS`) | Non | Non |
| `StatusMessage`| `Edm.String` | 220 | `BAPI_MSG` | Message de retour détaillé (ex: "Contact créé avec succès", "Erreur lors de la création") | Non | Non |

### Prérequis / Limitations connues

- Un **SAP Cloud Connector** est requis pour joindre le système SAP on-premise depuis CPI.
- L'utilisateur technique doit disposer des autorisations **S_RFC** et des objets d'autorisation **B_BUPA_*** nécessaires aux opérations Business Partner.
- Ce service est un développement custom **SEGW** ; il ne s'appuie pas sur l'API standard `API_BUSINESS_PARTNER`. Son développement et son transport doivent donc être prévus.

---

## Étape 1 : Paramétrage Prérequis dans SAP S/4HANA (Customizing)

Avant de commencer le développement, configurez l'environnement fonctionnel Business Partner :

1. **Création du Groupement de BP (Grouping)** :
   - Rendez-vous sur la transaction **BUC2** ou via le guide SPRO : *Composants applicatifs cross-applications -> Business Partner -> Paramètres de base -> Plages de numéros et groupements -> Définir groupements et attribuer plages de numéros*.
   - Créez le groupement **`ZC`**.
   - Assignez-lui une plage de numéros interne (ex: numéro généré automatiquement compris entre `0010000000` et `0019999999`).
2. **Vérification du Rôle de BP de Contact** :
   - Validez que le rôle standard **`BUP001`** (Personne de contact) est actif dans l'environnement de développement.
3. **Vérification de la Catégorie de Relation de BP** :
   - Validez que la catégorie de relation standard **`BUR001`** (Est personne de contact pour) est disponible (Table `BUT050`).

---

## Étape 2 : Création de l'OData Service personnalisée (Gateway SEGW)

1. Ouvrez la transaction **`SEGW`** (SAP Gateway Service Builder) dans SAP S/4HANA.
2. Créez un nouveau projet :
   - **Projet** : `ZCONTACTS_PROJECT`
   - **Description** : *Service de synchronisation des contacts MDM*
   - **Type de génération** : *OData v2*
3. Dans l'arborescence du projet, faites un clic droit sur **Data Model** -> **Create** -> **Entity Type** :
   - **Nom de l'entité** : `Contact`
   - **Entity Set Name** : `ContactSet` (cocher la case *Create Entity Set*).
4. Ajoutez les propriétés de l'entité conformément au tableau « Propriétés de l'entité OData `Contact` » ci-dessus (identique à celui de [abap_specs.md](abap_specs.md)).
   - *Astuce de pro : Cochez `BpContactId` comme **Key Property**.*
5. Cliquez sur le bouton **Generate Runtime Objects** (icône de roue dentée rouge/blanche). Cela va générer automatiquement les classes d'implémentation (MPC, MPC_EXT, DPC, DPC_EXT).

---

## Étape 3 : Implémentation du Code ABAP de Création (BAPIs & Logique Métier)

1. Une fois les objets de runtime générés, ouvrez le dossier **Service Implementation** -> **ContactSet** de votre projet SEGW.
2. Clic droit sur **Create (Write)** -> **Go to ABAP Workbench**.
3. SAP vous propose d'ouvrir la méthode `CONTACTSET_CREATE_ENTITY` de la classe d'extension DPC (`ZCL_ZCONTACTS_DPC_EXT`). Cliquez sur le bouton de modification (crayon) pour redéfinir la méthode.
4. Insérez le code ABAP complet disponible dans le fichier [abap_create_entity.abap](abap_create_entity.abap).
5. **Sauvegardez** et **activez** la méthode ainsi que la classe d'extension complète.

### Explications clés de la logique ABAP :
- **Validation du Parent** : La méthode lit d'abord la table `BUT000` pour vérifier que le BP parent est valide, évitant ainsi d'exécuter des BAPIs pour rien.
- **Contrôle Anti-Doublon** : La requête SQL combine la table de relations `BUT050` et la table d'identité `BUT000` pour s'assurer qu'aucun contact portant le même prénom et nom n'est déjà rattaché à ce parent. Si trouvé, elle retourne immédiatement son identifiant avec le statut `EXISTS` sans lever d'exception technique HTTP (qui bloquerait l'iFlow).
- **Enchaînement Transactionnel** : En cas d'erreur de n'importe quel BAPI de l'enchaînement, un `BAPI_TRANSACTION_ROLLBACK` est appelé pour garantir l'intégrité de la base de données SAP (pas de "BP orphelin" sans rôle ou sans relation). En cas de succès global, le `BAPI_TRANSACTION_COMMIT` valide l'écriture.

---

## Étape 4 : Configuration du SAP Cloud Connector

Pour que l'iFlow CPI (hébergé sur le Cloud SAP BTP) puisse interroger de manière sécurisée votre système S/4HANA installé On-Premise :

1. Connectez-vous à la console d'administration de votre **SAP Cloud Connector**.
2. Créez un nouveau **Mapping** entre votre environnement virtuel de cloud et votre système S/4HANA physique (On-Premise) :
   - **Back-end Type** : `ABAP System`
   - **Protocol** : `HTTPS` (ou `HTTP` selon votre configuration interne)
   - **Internal Host & Port** : L'adresse de votre serveur d'application SAP Gateway (ex: `s4hana-dev.internal:8443`).
   - **Virtual Host & Port** : Le nom d'hôte masqué exposé à CPI (ex: `s4hana-dev-virtual:8443`).
3. Dans la section **Resources Accessible** associée à ce mapping, ajoutez le chemin d'accès au service OData pour autoriser explicitement les appels :
   - **URL Path** : `/sap/opu/odata/sap/ZCONTACTS_SRV`
   - **Access Policy** : `Path and all sub-paths` (pour autoriser les appels sur les Entity Sets et métadonnées).

---

## Étape 5 : Conception et Développement de l'iFlow SAP CPI

Dans votre tenant **SAP Cloud Integration (CPI)**, créez un package d'intégration et concevez un **Integration Flow** (iFlow) synchrone selon le modèle ci-dessous :

```
[Postman/MDM] --(HTTPS POST)--> [HTTPS Sender]
                                      │
                                      ▼
                        [Groovy: Process Input Data]  <-- Validation et formatage
                                      │
                                      ▼
                        [OData V2 Receiver Adapter]  <-- Envoi vers S/4HANA via Cloud Connector
                                      │
                                      ▼
                     [Groovy: Response Handler]  <-- Normalisation JSON et HTTP 200 fonctionnel
                                      │
                                      ▼
                             [Exception Subprocess]  <-- Capturé en cas d'erreur réseau/SAP
                                      │
                                      ▼
                         [Groovy: Error Handler Script] <-- Renvoi d'un JSON propre
```

### Éléments constitutifs à configurer :

1. **HTTPS Sender Adapter** :
   - **Address** : `/v1/sap/contacts`
   - **User Role** : `ESBMessaging.send` (ou authentification par certificat client / OAuth).
2. **Groovy Script : Process Input Data** :
   - Créez un nouveau script Groovy dans les ressources de votre iFlow et collez-y le contenu du fichier [groovy_process_data.groovy](groovy_process_data.groovy).
   - Ce script valide la présence des champs obligatoires (`BpParent`, `FirstName`, `LastName`, ainsi que `Country` lorsqu'une adresse est renseignée) pour éviter d'envoyer des requêtes invalides à SAP, formate automatiquement le pays en majuscules et génère la date système par défaut si vide. Les payloads invalides reçoivent `HTTP 400` avec `StatusCode: ERROR`.
3. **OData V2 Receiver Adapter** (Connexion vers SAP S/4HANA) :
   - **Address** : `https://s4hana-dev-virtual:8443/sap/opu/odata/sap/ZCONTACTS_SRV`
   - **Proxy Type** : `On-Premise`
   - **Location ID** : (Entrez le Location ID de votre Cloud Connector si applicable)
   - **Authentication** : `Basic` (Saisir un utilisateur technique SAP de type système ayant les autorisations sur SEGW et les BAPIs de création de BP).
   - **Resource Path** : `ContactSet`
   - **Operation** : `CREATE`
4. **Groovy Script : Response Handler** :
   - Ajoutez, après l'adaptateur OData V2 sur le chemin de succès, le script [groovy_response_handler.groovy](groovy_response_handler.groovy).
   - Il désencapsule la réponse OData V2 et impose `HTTP 200` pour les retours fonctionnels `SUCCESS`, `EXISTS` ou `ERROR`.
5. **Exception Subprocess (Gestion des exceptions réseau/HTTP)** :
   - Ajoutez un composant *Exception Subprocess* pour intercepter toutes les erreurs de communication (ex: Gateway SAP indisponible, erreur 500 inattendue).
   - À l'intérieur, intégrez le script Groovy disponible dans [groovy_error_handler.groovy](groovy_error_handler.groovy). Ce script extrait le message d'erreur d'origine et le retourne sous la forme d'un JSON synchrone propre de format identique aux retours standards.

---

## Étape 6 : Tests Unitaires et Validation de bout en bout avec Postman

### Scénario de Test 1 : Création nominale (Succès)
1. Ouvrez Postman.
2. Créez une nouvelle requête **POST** vers l'URL exposée par votre CPI : `https://<cpi-tenant-url>/http/v1/sap/contacts`.
3. Configurez l'onglet **Authorization** (ex. Basic Auth ou Bearer Token selon vos paramètres CPI).
4. Dans l'onglet **Body**, sélectionnez `raw` et le format `JSON`.
5. Copiez-y le payload disponible dans [postman_payload_create.json](postman_payload_create.json).
6. Cliquez sur **Send**.

#### Résultat attendu :
- **Statut HTTP** : `200 OK`
- Le retour JSON correspond au fichier [postman_response_success.json](postman_response_success.json), affichant le `BpContactId` généré par la plage de numéros SAP et le message de validation.

---

### Scénario de Test 2 : Détection de doublons (Idempotence)
1. Renvoyez exactement la même requête POST avec le même nom, prénom et même ID de BP parent.

#### Résultat attendu :
- **Statut HTTP** : `200 OK`
- Le retour JSON affiche l'identifiant du contact existant créé lors de l'Étape 1, avec le code de statut `'EXISTS'` :
```json
{
  "BpParent": "10000123",
  "FirstName": "Jean",
  "LastName": "Dupont",
  "Street": "Rue de Rivoli",
  "HouseNumber": "42",
  "PostalCode": "75001",
  "City": "Paris",
  "Country": "FR",
  "Region": "11",
  "Language": "F",
  "BpContactId": "50000842",
  "StatusCode": "EXISTS",
  "StatusMessage": "Un contact similaire (ID: 50000842) existe déjà pour ce BP Parent."
}
```

---

### Scénario de Test 3 : BP Parent Inexistant
1. Envoyez une requête POST avec un identifiant de BP parent invalide ou inexistant (ex: `99999999`).

#### Résultat attendu :
- **Statut HTTP** : `200 OK` (Le service traite l'erreur de manière logique dans SAP sans planter)
- Le retour JSON affiche :
```json
{
  "BpParent": "99999999",
  "FirstName": "Jean",
  "LastName": "Dupont",
  ...
  "BpContactId": "",
  "StatusCode": "ERROR",
  "StatusMessage": "Le BP Parent 99999999 n'existe pas dans le système SAP."
}
```

---

## Gestion des Erreurs & Monitoring

Pour suivre et diagnostiquer le comportement de votre interface en production :

1. **Dans SAP S/4HANA (Backend)** :
   - **Transaction `/IWFND/ERROR_LOG`** : Permet de monitorer et d'analyser les requêtes OData entrantes rejetées par SAP Gateway.
   - **Transaction `SLG1` (Objet `BUPA`)** : Permet d'analyser les logs applicatifs liés à la création de Business Partners.
2. **Dans SAP CPI (Middleware)** :
   - Accédez au tableau de bord **Monitor Message Processing** de SAP CPI.
   - Activez le niveau de trace à `Trace` ou `Debug` en cours de test pour visualiser l'état du payload entre chaque étape de script Groovy et pour suivre les transactions entrantes et sortantes.
