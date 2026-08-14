# Orchestration CPI de BAPIs SAP Standards via RFC (sans code ABAP custom)

Ce guide décrit comment orchestrer, de manière **synchrone, séquentielle et transactionnelle**, les trois BAPIs SAP standards nécessaires pour créer un Business Partner de type personne, lui attribuer le rôle de contact et le lier au BP Parent, directement depuis votre middleware **SAP CPI (Cloud Integration)** sans aucun développement de code ABAP ou RFC custom côté SAP S/4HANA.

---

## 1. Pourquoi cette démarche ?

En utilisant les BAPIs standards, vous garantissez la compatibilité et l'évolutivité de l'intégration tout en gardant l'intelligence de l'orchestration dans le middleware CPI.

Puisque les écritures SAP doivent s'effectuer au sein de la même transaction (**Logical Unit of Work — LUW**), l'iFlow SAP CPI doit obligatoirement ouvrir une **session transactionnelle d'échange RFC** et maintenir cette même session ouverte tout au long des quatre appels consécutifs. En cas d'échec de l'un des BAPIs, la session est fermée sans commit, ce qui équivaut à un **ROLLBACK** automatique côté SAP.

---

## 2. Diagramme d'Orchestration Sequentielle dans CPI

L'iFlow CPI reçoit un unique payload JSON synchrone depuis Postman et exécute les étapes suivantes :

```text
  [ Client Postman (Payload Unique JSON) ]
                      │
                      ▼ (HTTPS Sender : /v1/sap/bapi-orchestration)
  ┌───────────────────────────────────────────────────────────┐
  │ 1. Script Groovy : Validation & XML BAPI_BUPA_CREATE...   │ [groovy_bapi_create_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPA_CREATE_FROM_DATA)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 2. Request Reply : Création du BP Personne                │ (Génère le numéro interne)
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 3. Script Groovy : Extraction de l'ID & XML Rôle_ADD      │ [groovy_bapi_role_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPA_ROLE_ADD_2)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 4. Request Reply : Attribution du Rôle de Contact         │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 5. Script Groovy : Dates SAP & XML Relation_CREATE        │ [groovy_bapi_relation_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_BUPR_CONTP_CREATE)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 6. Request Reply : Rattachement au BP Parent (BUR001)     │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 7. Script Groovy : XML BAPI_TRANSACTION_COMMIT            │ [groovy_bapi_commit_mapper.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (RFC : BAPI_TRANSACTION_COMMIT)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 8. Request Reply : Validation Transactionnelle Globale   │
  └───────────────────────────┬───────────────────────────────┘
                              │ (XML de Réponse RFC)
                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │ 9. Script Groovy : Formatage de la Réponse Finale de Succès│ [groovy_bapi_response_handler.groovy]
  └───────────────────────────┬───────────────────────────────┘
                              │ (HTTP 201 Created)
                              ▼
           [ Réponse JSON Unique renvoyée au Client ]
```

---

## 3. Composants requis dans l'iFlow CPI

| Composant | Quantité | Rôle / Configuration dans CPI |
| --- | --- | --- |
| **HTTPS Sender** | 1 | Reçoit le JSON. Endpoint : `/v1/sap/bapi-orchestration`. |
| **Groovy Script** | 5 | Traduisent les formats de données, contrôlent les retours de tables d'erreur `RETURN`, et lient les ID créés. |
| **Request Reply** | 4 | Exécutent de manière synchrone les appels RFC vers SAP. |
| **RFC Receiver** | 4 | Adaptateurs liés à chaque *Request Reply*. **Crucial :** Cochez l'option **"Keep Session Open"** (ou configurez une session d'échange partagée) pour garantir que les 4 appels s'exécutent dans le même processus de travail SAP (Work Process / LUW). |
| **Exception Subprocess** | 1 | Intercepte les erreurs réseau ou d'échec de BAPI. Appel de la méthode `handleError` dans `groovy_bapi_response_handler.groovy` pour renvoyer un statut `502` propre. |

---

## 4. Les Fichiers Sources d'Intégration du Dossier

Tous les scripts requis sont déjà programmés avec une gestion défensive des types (pas de variable générique `@DATA(...)` ni d'incompatibilité sur les types de chaîne de caractères) :

1. **`groovy_bapi_create_mapper.groovy`** : Valide le payload unique de Postman, sauvegarde les attributs en propriétés d'échange Camel et structure le XML d'importation pour `BAPI_BUPA_CREATE_FROM_DATA`.
2. **`groovy_bapi_role_mapper.groovy`** : Contrôle la table `RETURN` de la création de BP. Si aucune erreur n'est détectée, extrait le numéro du Business Partner créé (`BUSINESSPARTNER`), le mémorise dans la propriété `bapi_prop_bp_contact_created` et écrit le XML de requête pour `BAPI_BUPA_ROLE_ADD_2`.
3. **`groovy_bapi_relation_mapper.groovy`** : Vérifie l'ajout de rôle, convertit les dates de début et de fin sous la forme technique SAP (`AAAAMMJJ` / défaut `99991231` pour la date de fin) et génère la structure XML pour `BAPI_BUPR_CONTP_CREATE`.
4. **`groovy_bapi_commit_mapper.groovy`** : Vérifie la réussite de l'association de relation et prépare le XML RFC pour `BAPI_TRANSACTION_COMMIT` (avec l'argument `WAIT = X` pour assurer la synchronisation).
5. **`groovy_bapi_response_handler.groovy`** :
   - Méthode nominale `processData` : Assure la validation finale du commit et génère une réponse JSON unifiée de succès (`HTTP 201 Created`).
   - Méthode d'erreur `handleError` (à configurer dans l'Exception Subprocess) : Formate proprement les retours d'erreurs techniques ou fonctionnelles en un payload JSON homogène (`HTTP 502 Bad Gateway`).

---

## 5. Exemple de Test Complet avec Postman

### Requête unique (Body JSON)
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

### Réponse unifiée de succès attendue (`201 Created`)
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

### Réponse d'erreur homogène en cas d'échec d'un BAPI (`502 Bad Gateway`)
Si, par exemple, le rôle `BUP001` ou le groupement `ZC` n'est pas autorisé par le customizing SAP pour ce type de contact, le deuxième script intercepte l'erreur dans la table `RETURN` de SAP, l'Exception Subprocess s'exécute et retourne :
```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont BAPI",
  "BpContactId": "",
  "StatusCode": "ERROR",
  "StatusMessage": "Échec de BAPI_BUPA_CREATE_FROM_DATA : Le groupement ZC n'est pas configuré pour les attributions internes de numéros."
}
```
*Note : Étant donné que la session d'échange est fermée sur erreur sans l'appel de `BAPI_TRANSACTION_COMMIT`, S/4HANA annule automatiquement toutes les écritures temporaires (Rollback implicite), éliminant tout risque de base inconsistante (pas de Business Partner créé sans son rôle de contact).*
