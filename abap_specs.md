# Architecture et Spécification Technique de l'OData Service

Ce document décrit en détail l'architecture, la modélisation et le dictionnaire de données pour l'implémentation du service OData SAP Gateway dans la transaction **SEGW** pour la création de contacts (Business Partner de type Personne).

---

## 1. Modélisation de l'OData Service (SEGW)

Le service OData sera conçu avec une structure plate (Flat Entity Structure) optimisée pour un échange synchrone à haute performance via SAP CPI.

### Entity Type: `Contact`
- **Nom technique de l'entité** : `Contact`
- **Entity Set** : `ContactSet`

### Propriétés de l'Entité (Entity Properties)

| Nom de la Propriété (OData) | Type OData | Élément de Donnée SAP (Data Element) | Rôle / Description | Clé | Obligatoire |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `BpParent` | `Edm.String` | `BU_PARTNER` | Numéro du BP Parent (Organisation / Client / Fournisseur) | Non | Oui |
| `FirstName` | `Edm.String` | `BU_NAME_FIRST` | Prénom du contact (BUT000-NAME_FIRST) | Non | Oui |
| `LastName` | `Edm.String` | `BU_NAME_LAST` | Nom de famille du contact (BUT000-NAME_LAST) | Non | Oui |
| `Street` | `Edm.String` | `AD_STREET` | Nom de la rue (ADRC-STREET) | Non | Non |
| `HouseNumber` | `Edm.String` | `AD_HSNM1` | Numéro de rue / maison (ADRC-HOUSE_NUM1) | Non | Non |
| `PostalCode` | `Edm.String` | `AD_PSTCD1` | Code postal (ADRC-POST_CODE1) | Non | Non |
| `City` | `Edm.String` | `AD_CITY1` | Ville (ADRC-CITY1) | Non | Non |
| `Country` | `Edm.String` | `LAND1` | Code pays à 2 caractères (ADRC-COUNTRY) | Non | Oui (si adresse présente) |
| `Region` | `Edm.String` | `REGIO` | Code de la région (ADRC-REGION) | Non | Non |
| `Language` | `Edm.String` | `SPRAS` | Langue de communication (ADRC-LANGU) | Non | Non |
| `DateFrom` | `Edm.DateTime`| `BU_DATFROM` | Date de début de validité de la relation (BUT050-DATE_FROM) | Non | Non |
| `DateTo` | `Edm.DateTime`| `BU_DATTO` | Date de fin de validité de la relation (BUT050-DATE_TO) | Non | Non |
| `BpContactId` | `Edm.String` | `BU_PARTNER` | **Généré par SAP** : Numéro interne du nouveau Contact créé | **Oui**| Non |
| `StatusCode` | `Edm.String` | `CHAR10` | Statut du traitement (`SUCCESS` / `ERROR` / `EXISTS`) | Non | Non |
| `StatusMessage`| `Edm.String` | `BAPI_MSG` | Message de retour détaillé (ex: "Contact créé avec succès", "Erreur lors de la création") | Non | Non |

---

## 2. Dictionnaire de Données SAP & Customizing

Pour assurer le bon fonctionnement de l'interface, le paramétrage SAP S/4HANA (Customizing) suivant doit être validé ou créé.

### A. Plage de numéros et Groupement (Grouping)
Dans la transaction **BUC2** (ou via SPRO : *Cross-Application Components -> SAP Business Partner -> Business Partner -> Basic Settings -> Number Ranges and Groupings*) :
- Créer ou valider un groupement nommé **`ZC`**.
- Ce groupement doit être configuré pour une **Attribution Interne de Numéros** (Internal Number Assignment).
- La table correspondante dans le dictionnaire SAP est **`TB001`** (champ `BU_GROUP` = 'ZC').

### B. Catégorie et Rôle du Business Partner (BP Role)
- **Catégorie de BP** : **`1`** (Person) - Ce paramètre est directement fourni au BAPI.
- **Rôle de BP** (transaction **BP** / customizing) : **`BUP001`** (Contact Person / Personne de contact).
- Table de base de données liée : **`BUT100`** (champ `RLTYP` = 'BUP001').

### C. Catégorie de Relation (Relationship Category)
- Pour lier un BP contact (Personne) à un BP parent (Organisation), la catégorie de relation standard SAP est **`BUR001`** (Contact Person / Est personne de contact pour).
- Table de base de données liée : **`BUT050`** (champ `RELTYP` = 'BUR001').
