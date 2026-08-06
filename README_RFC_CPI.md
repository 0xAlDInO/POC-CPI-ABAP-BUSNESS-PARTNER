# Création de contact via RFC — CPI ↔ SAP S/4HANA

Cette variante remplace OData par une fonction RFC distante unique : `ZRFC_BP_CONTACT_EQ1`.

Le client appelle CPI en JSON. CPI appelle ensuite une seule fonction RFC SAP ; cette fonction crée le Business Partner personne, récupère son numéro interne, ajoute le rôle, puis crée la relation avec le BP parent dans **la même LUW SAP**. En cas d'erreur à une des étapes, elle exécute un rollback.

```text
Client / Postman (JSON)
  → HTTPS Sender CPI
  → Groovy : validation et JSON → XML RFC
  → Router (erreur HTTP 400)
  → Request Reply
  → RFC Receiver Adapter (ZRFC_BP_CONTACT_EQ1)
  → Groovy : XML RFC → JSON
  → réponse HTTP

Exception Subprocess
  → Groovy : erreur technique → HTTP 502
```

## 1. Contrat RFC

Créez d'abord dans **SE11** le type de table `ZTT_BAPIRET2` : catégorie **Standard Table**, ligne de type `BAPIRET2`, clé standard. Créez ensuite la fonction `ZRFC_BP_CONTACT_EQ1` dans la transaction **SE37**, puis cochez **Remote-Enabled Module** dans ses attributs. Le code complet et l'interface à créer sont dans [abap_rfc_create_bp_contact.abap](abap_rfc_create_bp_contact.abap).

| Sens | Paramètre | Type DDIC | Règle |
| --- | --- | --- | --- |
| Import | `IV_BP_PARENT` | `BU_PARTNER` | Obligatoire ; CPI l'envoie sur 10 caractères avec zéros à gauche. |
| Import | `IV_FIRST_NAME`, `IV_LAST_NAME` | `BU_NAMEP_F`, `BU_NAMEP_L` | Obligatoires. |
| Import | `IV_BP_CATEGORY` | `BU_TYPE` | Défaut `1` ; seuls les contacts personnes sont admis. |
| Import | `IV_GROUPING` | `BU_GROUP` | Défaut `ZC`, avec attribution interne de numéro. |
| Import | `IV_BP_ROLE` | `BU_PARTNERROLE` | Défaut `BUP001`. |
| Import | Adresse | Types `AD_*`, `LAND1`, `REGIO` | Optionnelle ; si elle est présente, le pays est obligatoire. |
| Import | `IV_LANGUAGE` | `SPRAS` | Optionnelle ; langue de correspondance de la personne, indépendante de l’adresse. |
| Import | `IV_DATE_FROM`, `IV_DATE_TO` | `DATS` | Dans le payload RFC : `YYYYMMDD`. Défauts : aujourd'hui / `99991231`. En test SE37, saisir le format de date de l'utilisateur SAP. |
| Export | `EV_BP_CONTACT` | `BU_PARTNER` | Numéro généré par SAP, avec ses zéros à gauche. |
| Export | `EV_STATUS_CODE` | `CHAR10` | `SUCCESS`, `EXISTS`, `LOCKED` ou `ERROR`. |
| Export | `EV_STATUS_MESSAGE` | `BAPI_MSG` | Message destiné à CPI. |
| Changing | `CT_RETURN` | `ZTT_BAPIRET2` | Détails BAPI exploitables dans le monitor CPI. En cas de succès, une dernière ligne `S` reprend aussi le numéro BP créé. |

Ne changez pas un numéro BP en entier dans CPI ou Postman : `0005200001` et `5200001` ne sont pas la même représentation RFC.

### Création exacte de l'interface dans SE37

Créez **tous** ces paramètres avant de coller le source code. Un champ `IV_STREET is unknown` ou `CT_RETURN is unknown` signifie qu'il n'a pas été créé dans l'interface du FM.

Dans l'onglet **Import**, ajoutez les lignes suivantes. Cochez *Optional* pour toutes les lignes marquées « Oui ».

| Parameter Name | Associated Type | Optional |
| --- | --- | --- |
| `IV_BP_PARENT` | `BU_PARTNER` | Non |
| `IV_FIRST_NAME` | `BU_NAMEP_F` | Non |
| `IV_LAST_NAME` | `BU_NAMEP_L` | Non |
| `IV_BP_CATEGORY` | `BU_TYPE` | Oui |
| `IV_GROUPING` | `BU_GROUP` | Oui |
| `IV_BP_ROLE` | `BU_PARTNERROLE` | Oui |
| `IV_STREET` | `AD_STREET` | Oui |
| `IV_HOUSE_NUMBER` | `AD_HSNM1` | Oui |
| `IV_POSTAL_CODE` | `AD_PSTCD1` | Oui |
| `IV_CITY` | `AD_CITY1` | Oui |
| `IV_COUNTRY` | `LAND1` | Oui |
| `IV_REGION` | `REGIO` | Oui |
| `IV_LANGUAGE` | `SPRAS` | Oui |
| `IV_DATE_FROM` | `DATS` | Oui |
| `IV_DATE_TO` | `DATS` | Oui |

Dans l'onglet **Export**, ajoutez `EV_BP_CONTACT TYPE BU_PARTNER`, `EV_STATUS_CODE TYPE CHAR10` et `EV_STATUS_MESSAGE TYPE BAPI_MSG`.

Dans l'onglet **Changing**, ajoutez `CT_RETURN TYPE ZTT_BAPIRET2` et cochez *Optional*. Ne créez rien dans l'onglet **Tables**.

Enfin, le nom entre `FUNCTION` et `ENDFUNCTION` dans le source doit être **exactement** celui du FM créé. Cette version utilise :

```abap
FUNCTION zrfc_bp_contact_eq1.
```

Le bloc « Local Interface » est généré par SE37 : après avoir créé les paramètres, vérifiez que `IV_BP_ROLE` est de type `BU_PARTNERROLE` et que tous les paramètres marqués optionnels dans le tableau le sont réellement. Le commentaire ABAP seul ne modifie pas le metadata RFC.

## 2. Logique ABAP exécutée dans une seule transaction

1. Validation des champs et contrôle que le BP parent existe.
2. Prise d'un verrou logique sur le BP parent, puis recherche d'un contact ayant le même nom/prénom et une période de validité qui chevauche celle demandée. En cas de doublon, la fonction renvoie `EXISTS` et son numéro sans créer de nouveau BP.
3. `BAPI_BUPA_CREATE_FROM_DATA` crée le BP personne. Son export `BUSINESSPARTNER` est recopié immédiatement dans `EV_BP_CONTACT` et récapitulé dans la dernière ligne de `CT_RETURN`.
4. `BAPI_BUPA_ROLE_ADD_2` ajoute le rôle `BUP001` en utilisant ce numéro généré.
5. `BAPI_BUPR_CONTP_CREATE` crée la relation avec le parent, toujours avec le même numéro généré.
6. `BAPI_TRANSACTION_COMMIT` est exécuté seulement si les trois BAPIs ont réussi ; son retour est contrôlé avant de répondre `SUCCESS`. Sinon `BAPI_TRANSACTION_ROLLBACK` annule toutes les écritures.

Avant activation, vérifiez dans votre système que les signatures des trois BAPIs correspondent à votre release et que le groupement `ZC`, le rôle `BUP001` et la relation `BUR001` sont actifs.

## 3. Prérequis SAP et sécurité

1. Activez et testez le FM dans **SE37** avec un BP parent de recette.
2. Créez un utilisateur de communication dédié. Limitez `S_RFC` au groupe de fonctions qui contient `ZRFC_BP_CONTACT_EQ1`, plus les autorisations Business Partner nécessaires (`B_BUPA_*` selon vos règles de sécurité).
3. Ne rendez pas les BAPIs de création directement accessibles à CPI : CPI doit appeler seulement votre FM Z, qui applique validation, anti-doublon et rollback.
4. Dans **SAP Cloud Connector**, créez le mapping vers le système ABAP puis autorisez l'accès RFC au FM ou à son groupe de fonctions selon le paramétrage de votre version.
5. Utilisez un canal chiffré (SNC/TLS selon votre paysage) et stockez les identifiants dans le **Security Material** CPI, jamais dans un script.

## 4. Composants nécessaires dans l’iFlow CPI

| Zone | Composant | Quantité | Usage |
| --- | --- | ---: | --- |
| Sender | HTTPS Sender | 1 | Reçoit la requête JSON du client. |
| Process principal | Groovy Script | 2 | Transforme JSON → XML RFC, puis XML RFC → JSON. |
| Process principal | Router | 1 | Arrête les validations techniques en HTTP 400. |
| Process principal | Request Reply | 1 | Attend de façon synchrone la réponse RFC. |
| Receiver | RFC Receiver Adapter | 1 | Appelle `ZRFC_BP_CONTACT_EQ1` via Cloud Connector. |
| Process principal | End Message | 2 | Termine le chemin nominal et le chemin de validation. |
| Exception Subprocess | Exception Start Event | 1 | Capture les pannes de connectivité, authentification et RFC. |
| Exception Subprocess | Groovy Script + End Message | 1 + 1 | Formate une réponse JSON HTTP 502. |

N'utilisez ni OData Receiver, ni token CSRF, ni trois appels RFC indépendants : la fonction Z assure déjà l'ordre et l'atomicité dans SAP.

## 5. Construction de l’iFlow, étape par étape

### Étape 1 — HTTPS Sender

1. Créez l’artefact `IFLOW_CREATE_BP_CONTACT_RFC`.
2. Ajoutez un **HTTPS Sender** avec l’adresse `/v1/sap/contacts-rfc`.
3. Appliquez le rôle CPI d’envoi approprié et une authentification approuvée par votre équipe de sécurité.

### Étape 2 — Mapper la requête client vers le RFC

1. Ajoutez un **Groovy Script** après le Sender et importez [groovy_rfc_request_mapper.groovy](groovy_rfc_request_mapper.groovy).
2. Ajoutez un **Router** juste après ce script.
3. Ajoutez la condition de sortie validation :

   ```text
   ${property.is_integration_failed} = 'true'
   ```

4. Reliez cette branche à un **End Message**. La Default Route continue vers SAP.

Le script valide les champs requis, normalise les valeurs par défaut et transforme les dates ISO `YYYY-MM-DD` reçues du client en dates RFC `YYYYMMDD`. `Language` représente la langue de correspondance du contact, pas la langue de son adresse.

### Étape 3 — Appeler le RFC SAP

1. Ajoutez un **Request Reply** sur la Default Route.
2. Ajoutez un participant receiver et choisissez l’adaptateur **RFC Receiver**.
3. Dans l’adaptateur, configurez le système virtuel Cloud Connector, le type de proxy **On-Premise**, le Location ID si nécessaire et le Security Material CPI.
4. Dans le traitement, sélectionnez la fonction RFC `ZRFC_BP_CONTACT_EQ1` et le format XML correspondant à son interface.
5. Reliez l’adaptateur au Request Reply.

Le body produit par le premier script est de la forme suivante ; il doit correspondre exactement aux noms des paramètres SE37 :

```xml
<ZRFC_BP_CONTACT_EQ1>
  <IV_BP_PARENT>0005200000</IV_BP_PARENT>
  <IV_FIRST_NAME>Jean</IV_FIRST_NAME>
  <IV_LAST_NAME>Dupont</IV_LAST_NAME>
  <IV_BP_CATEGORY>1</IV_BP_CATEGORY>
  <IV_GROUPING>ZC</IV_GROUPING>
  <IV_BP_ROLE>BUP001</IV_BP_ROLE>
  <IV_DATE_FROM>20260806</IV_DATE_FROM>
  <IV_DATE_TO>99991231</IV_DATE_TO>
</ZRFC_BP_CONTACT_EQ1>
```

### Étape 4 — Renvoyer la réponse au client

1. Après le Request Reply, ajoutez un second **Groovy Script** et importez [groovy_rfc_response_handler.groovy](groovy_rfc_response_handler.groovy).
2. Ajoutez un **End Message**.

Le script transforme les exports RFC en JSON et applique ce contrat :

| Retour RFC | HTTP CPI | Effet |
| --- | ---: | --- |
| `SUCCESS` | 201 | Contact, rôle et relation créés. |
| `EXISTS` | 409 | Aucun nouveau BP créé ; le numéro existant est retourné. |
| `LOCKED` | 423 | Une demande concurrente est en cours pour ce BP parent ; le client peut réessayer. |
| `ERROR` | 400 | Erreur métier ou donnée non valide. |
| Exception RFC/CPI | 502 | Erreur technique ; voir l’Exception Subprocess. |

### Étape 5 — Exception Subprocess

1. Ajoutez un **Exception Subprocess** non relié au flux principal.
2. Placez [groovy_rfc_error_handler.groovy](groovy_rfc_error_handler.groovy), puis un **End Message**.
3. En production, remplacez si nécessaire le détail technique envoyé au client par un identifiant de corrélation et conservez le détail seulement dans les logs CPI.

## 6. Tests

### Test SE37

Dans **SE37**, utilisez un BP parent existant et saisissez les dates selon le format défini dans votre profil SAP, et non le format technique RFC. Avec un profil français, entrez par exemple `06.08.2026` et `31.12.9999` (ou utilisez l’aide de saisie du champ). `20260806` et `99991231` sont réservés au payload XML RFC transmis par CPI.

Exécutez ensuite la fonction. Vérifiez :

- `EV_STATUS_CODE = SUCCESS` ;
- `EV_BP_CONTACT` est renseigné sur 10 caractères ;
- la dernière ligne `S` de `CT_RETURN` reprend le même numéro BP ;
- le rôle `BUP001` et la relation `BUR001` existent dans BP ;
- `CT_RETURN` ne contient pas de type `E`, `A` ou `X`.

### Test Postman via CPI

```text
POST https://<tenant-cpi>/http/v1/sap/contacts-rfc
Content-Type: application/json
```

```json
{
  "BpParent": "0005200000",
  "FirstName": "Jean",
  "LastName": "Dupont RFC",
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

Résultat attendu : HTTP `201` avec `StatusCode: SUCCESS` et le numéro généré dans `BpContactId`. Testez également un champ absent (`400`), un parent inconnu (`400`), une période invalide (`400`), deux demandes identiques simultanées (`423` / `LOCKED`, puis `409` / `EXISTS` après réessai) et une indisponibilité SAP (`502`).

## 7. Limites et exploitation

- Le verrou logique sur le BP parent empêche deux appels parallèles de ce RFC de franchir simultanément le contrôle de doublon. L’anti-doublon reste toutefois fondé sur nom/prénom et période ; si cette règle n’est pas assez discriminante, ajoutez une clé métier ou un identifiant MDM dans une table Z.
- Les types DDIC et les autorisations exactes dépendent de votre version S/4HANA. Vérifiez-les dans SE37, SU53 et le customizing BP avant mise en production.
