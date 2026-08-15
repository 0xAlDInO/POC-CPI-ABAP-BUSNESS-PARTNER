# Modèle Enterprise d'Orchestration SAP CPI : Sub-Processes & Data Management

Ce dossier contient l'architecture complète d'intégration pour SAP Cloud Integration (CPI) basée sur le modèle d'entreprise référence. Il combine **Local Integration Processes**, **Router**, **General Splitter**, **DataStore Management**, **Delay**, et **Process Calls**.

---

## 1. Architecture Globale du Flux (Design Pattern CPI)

```text
  [ INBOUND MSG ] ──► [ Log Inbound ] ──► [ Common Config ] ──► [ Router 1 ]
                                                                   │
                                           ┌───────────────────────┴───────────────────────┐
                                           ▼                                               ▼
                                  (Path A: BP Relations)                         (Path B: BP Creation)
                                           │                                               │
                                  [ Process Call Rel ]                             [ Configurations ]
                                                                                           │
                                                                                       [ Delay ]
                                                                                           │
                                                                                 [ PreExit Router ]
                                                                                           │
                                                                   ┌───────────────────────┴───────────────────────┐
                                                                   ▼                                               ▼
                                                         (PreExit Enabled)                       (PreExit Disabled)
                                                                   │                                               │
                                                       [ Pre-Exit SubProcess ]                   [ Define Org Map ]
                                                                                                           │
                                                                                                   [ Process Org Name ]
                                                                                                           │
                                                                                                   [ General Splitter ]
                                                                                                           │
                                                                                                   [ DataStore / Restores ]
```

---

## 2. Rôle des Composants et des Scripts Groovy

### A. Logging & Configuration Inbound
* **`groovy_log_inbound.groovy`** :
  * Capture le payload entrant et l'attache au journal d'exécution (Message Monitor Attachment).
  * Sauvegarde le corps du message initial dans la propriété Camel `OriginalInboundPayload`.
* **`groovy_common_config.groovy`** :
  * Définit les propriétés système globales (`MaxRetryAttempts`, `DelayDurationMillis`, `PreExitEnabled`).
  * Force le code HTTP de succès à `200 OK` / `201 Created`.

### B. Routage & Découpage (Splitter / Router)
* **`groovy_relation_counter.groovy`** :
  * Compte dynamiquement le nombre de relations/contacts dans le message.
  * Définit la propriété `HasRelations` à `true` ou `false` pour alimenter la décision du **Router 1**.
* **Router 1** :
  * Si `HasRelations == 'true'`, déroute le flux vers le sous-processus `Call Process BP Rel`.
  * Sinon, poursuit vers la création classique de Business Partner.

### C. Persistance & DataStore (Sauvegarde & Restauration)
* **`groovy_datastore_backup.groovy`** :
  * Génère un identifiant d'entrée unique (`SAP_DataStoreEntryId`) et cible la table de données `BP_Relations_Backup_DS`.
  * Permet de sauvegarder temporairement les relations non encore associées pour un traitement différé asynchrone.
* **`groovy_restore_split_payload.groovy`** :
  * Réagrège le payload scindé par le **General Splitter** avec la réponse retournée par SAP.
  * Positionne le header `CamelHttpResponseCode` à `201 Created`.

---

## 3. Matrice des Fichiers dans ce Dossier

| Nom du Fichier | Description |
| :--- | :--- |
| `groovy_log_inbound.groovy` | Script de logging entrant et sauvegarde payload original |
| `groovy_common_config.groovy` | Script d'initialisation des paramètres runtime |
| `groovy_relation_counter.groovy` | Analyseur de relations pour branchement conditionnel Router |
| `groovy_datastore_backup.groovy` | Préparateur de headers pour DataStore Write |
| `groovy_restore_split_payload.groovy` | Reconstructeur de payload après Splitter & SubProcess |
| `sample_multi_bp_payload.json` | JSON d'exemple d'entrée avec organisation et relations |
| `sample_processed_response.json` | JSON de réponse agrégée finale HTTP 201 |

---

## 4. Instructions de Déploiement dans SAP CPI Tenant

1. **Création du Package CPI** : Dans votre workspace CPI, créez ou ouvrez le package `Business Partner Integration`.
2. **Import des Scripts** : Ajoutez les 5 scripts Groovy ci-dessus dans la section *Resources -> Scripts*.
3. **Configuration du Router & Splitter** :
   - Dans **Router 1**, configurez l'expression Non-XML / Property : `${property.HasRelations} == 'true'`.
   - Dans le **General Splitter**, configurez l'expression JSON path `/relations` ou `/businessPartner`.
4. **Configuration du DataStore Write** :
   - Configurez le composant DataStore avec `DataStore Name` = `BP_Relations_Backup_DS` et `Entry ID` = `${header.SAP_DataStoreEntryId}`.
