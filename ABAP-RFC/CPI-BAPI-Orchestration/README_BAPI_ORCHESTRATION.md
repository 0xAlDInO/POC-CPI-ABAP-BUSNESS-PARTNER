# Orchestration CPI de BAPIs SAP Standards via RFC — Guide Complet

Ce guide détaille comment concevoir, configurer et administrer l'intégration et l'orchestration transactionnelle de BAPIs SAP standards de bout en bout, en passant par **SAP CPI (Cloud Integration)** et le **SAP Cloud Connector (SCC)** vers votre système **SAP S/4HANA On-Premise**.

Cette méthode s'exécute de manière **synchrone et séquentielle** au sein d'une seule et unique **Logical Unit of Work (LUW)** SAP. Si l'un des appels échoue, l'intégralité des écritures est annulée automatiquement (**Rollback** implicite).

---

## 1. Architecture Globale et Séquence de Flux

L'iFlow CPI reçoit un unique payload JSON synchrone depuis le client externe (ex: Postman) contenant toutes les informations du contact et l'identifiant du parent.

```text
  [ Client Postman (JSON) ]
            │
            ▼ (HTTPS Sender : /v1/sap/bapi-orchestration)
  ┌───────────────────────────────────────────────────────────┐
  │ 1. Script Groovy : Validation & XML BAPI_BUPA_CREATE...   │ [groovy_bapi_create_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPA_CREATE_FROM_DATA)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 2. Request Reply 1 : Création du BP Personne              │ (Génère le numéro interne)
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 3. Script Groovy : Extraction de l'ID & XML Rôle_ADD      │ [groovy_bapi_role_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPA_ROLE_ADD_2)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 4. Request Reply 2 : Attribution du Rôle de Contact       │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 5. Script Groovy : Dates SAP & XML Relation_CREATE        │ [groovy_bapi_relation_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPR_CONTP_CREATE)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 6. Request Reply 3 : Rattachement au BP Parent (BUR001)     │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 7. Script Groovy : XML BAPI_TRANSACTION_COMMIT            │ [groovy_bapi_commit_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_TRANSACTION_COMMIT)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 8. Request Reply 4 : Validation Transactionnelle Globale   │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 9. Script Groovy : Formatage de la Réponse de Succès 201  │ [groovy_bapi_response_handler.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (JSON + HTTP 201 Created)
                              ▼
             [ Réponse unique renvoyée au client ]
```

---

## 2. Configuration du SAP Cloud Connector (SCC)

Le SAP Cloud Connector établit un tunnel TLS sécurisé entre votre sous-compte SAP BTP (où tourne CPI) et votre système SAP S/4HANA On-Premise.

### Étape A : Association du Sous-Compte BTP
1. Connectez-vous à la console d'administration de votre Cloud Connector local.
2. Cliquez sur **Add Subaccount** :
   - **Region** : Votre région BTP (ex: `cf.eu10`).
   - **Subaccount ID** : L'ID technique de votre sous-compte BTP (disponible sur le cockpit BTP).
   - **Subaccount User & Password** : Utilisateur technique habilité à connecter le SCC.

### Étape B : Mapping vers le Système ABAP (On-Premise)
1. Sélectionnez le sous-compte associé dans le menu supérieur.
2. Allez dans **Cloud To On-Premise** puis sur l'onglet **Access Control**.
3. Cliquez sur **Add** (bouton `+`) pour créer un mapping système :
   - **Back-end Type** : `ABAP System`
   - **Protocol** : `RFC` (ou `RFC_SNC` si chiffrement actif)
   - **Internal Host & Port** : Le nom d'hôte interne physique du serveur applicatif SAP (ex: `s4hana-app.internal:3200` ou load balancer).
   - **Virtual Host & Port** : Le nom virtuel exposé de manière anonymisée à SAP CPI (ex: `s4hana-virtual-rfc`). C'est ce nom virtuel qui sera renseigné dans vos adaptateurs CPI.

### Étape C : Autorisation des Modules de Fonction (Ressources RFC)
Par défaut, le Cloud Connector bloque tout appel réseau. Vous devez explicitement déclarer les BAPIs standards comme accessibles :
1. Sélectionnez le système virtuel créé ci-dessus.
2. Dans la table **Resources Accessible**, cliquez sur **Add** :
   - **Resource Name** : `BAPI_BUPA_CREATE_FROM_DATA`
   - **Naming Policy** : `Exact Name`
3. Répétez l'opération pour les autres BAPIs requis :
   - `BAPI_BUPA_ROLE_ADD_2` (Exact Name)
   - `BAPI_BUPR_CONTP_CREATE` (Exact Name)
   - `BAPI_TRANSACTION_COMMIT` (Exact Name)
4. *Alternative de commodité pour le développement / POC (à éviter en production) :* Déclarer le préfixe `BAPI_BUPA_*` et `BAPI_BUPR_*` avec la politique `Prefix` pour autoriser tous les appels associés.

---

## 3. Paramétrage des Composants dans l'iFlow SAP CPI

La configuration de l'iFlow doit garantir que la session RFC reste ouverte d'un appel à l'autre.

### 1. HTTPS Sender Adapter (Point d'Entrée)
- **Address** : `/v1/sap/bapi-orchestration`
- **User Role** : `ESBMessaging.send` (ou Client Certificate)

### 2. Les Blocs Request-Reply et Adaptateurs RFC
Pour chacun des quatre appels séquentiels, placez un composant **Request-Reply** et reliez sa sortie à un adaptateur **RFC Receiver** pointant vers le même système SAP virtuel.

#### Paramétrage obligatoire de l'Adaptateur RFC Receiver :
- **Destination Name** : (Si configuré dans les destinations de votre Cockpit BTP, sinon laissez vide).
- **Address** : `s4hana-virtual-rfc` (Nom de domaine virtuel configuré dans votre Cloud Connector).
- **Location ID** : Renseignez l'ID de localisation de votre Cloud Connector s'il est utilisé (ex: `PARIS_SCC`).
- **Proxy Type** : `On-Premise`
- **Authentication** : `User Credentials` (sélectionnez l'alias de vos identifiants SAP, configuré dans le Security Material de CPI).
- **RFC Session Handling (CRUCIAL) :**
  - Cochez impérativement l'option **`Keep Session Open`** (ou configurez un conteneur de transaction RFC partagé) sur les adaptateurs des étapes 1, 2 et 3.
  - Sur le dernier adaptateur (Étape 4 - `BAPI_TRANSACTION_COMMIT`), décochez cette option ou laissez-la fermer la session.
  *Cette option ordonne à l'adaptateur RFC de réutiliser la même connexion réseau (et donc la même Logical Unit of Work - LUW) pour tous les appels consécutifs. Sans cela, chaque BAPI s'exécutera dans des sessions isolées et aucune donnée ne sera persistée dans la base de données SAP S/4HANA.*

---

## 4. Les Scripts de Mapping Groovy

Voici la liste des fichiers inclus dans ce dossier pour orchestrer et surveiller l'exécution :

- **`groovy_bapi_create_mapper.groovy`** : Valide le JSON entrant, mémorise les valeurs d'origine (`BpParent`, `FirstName`, `LastName`, `Language`, `Street`, `HouseNumber`, `PostalCode`, `City`, `Country`, `Region`, `DateFrom`, `DateTo`) dans des propriétés d'échange et écrit le XML de requête pour `BAPI_BUPA_CREATE_FROM_DATA`.
- **`groovy_bapi_role_mapper.groovy`** : Parse le retour XML de la création du BP, vérifie l'absence de nœuds d'erreur (`TYPE = 'E'`) dans l'élément `RETURN`, extrait le code unique du Business Partner créé (`BUSINESSPARTNER`), le stocke dans la propriété `bapi_prop_bp_contact_created` et écrit le XML pour `BAPI_BUPA_ROLE_ADD_2`.
- **`groovy_bapi_relation_mapper.groovy`** : Analyse le retour d'ajout de rôle, convertit les dates sous format technique SAP (`AAAAMMJJ`), et génère l'XML pour `BAPI_BUPR_CONTP_CREATE`.
- **`groovy_bapi_commit_mapper.groovy`** : Valide la création de la relation et écrit le XML de commit `BAPI_TRANSACTION_COMMIT` avec l'argument d'attente active `WAIT = X`.
- **`groovy_bapi_response_handler.groovy`** :
  - **Méthode `processData` (Chemin Nominal) :** Valide le commit final, et génère le JSON de succès renvoyé au client externe avec un code de statut **`HTTP 201 Created`** (en positionnant l'en-tête Camel `CamelHttpResponseCode = 201`).
  - **Méthode `handleError` (Exception Subprocess) :** Intercepte les erreurs réseau ou d'échec de validation d'un BAPI standard pour construire une réponse d'erreur unifiée de statut **`HTTP 502 Bad Gateway`**.

---

## 5. Exemple de Jeu de Données de Test

### Payload Postman (HTTP POST) :
```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont BAPI",
  "BpCategory": "1",
  "Grouping": "ZC",
  "BpRole": "BUP001",
  "Street": "Rue de Rivoli",
  "HouseNumber": "42",
  "PostalCode": "75001",
  "City": "Paris",
  "Country": "FR",
  "Region": "11",
  "Language": "F",
  "DateFrom": "2026-08-06",
  "DateTo": "9999-12-31"
}
```

### Réponse unifiée de succès (`HTTP 201 Created`) :
```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont BAPI",
  "BpContactId": "0005300188",
  "StatusCode": "SUCCESS",
  "StatusMessage": "Le contact BP 0005300188 a été créé, son rôle attribué, et la relation de contact BUR001 validée avec succès."
}
```
