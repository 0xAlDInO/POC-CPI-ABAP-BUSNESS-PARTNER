# Création de contact via RFC — Version Orientée Objet Globale (SE24 + Text Symbols)

Cette version représente l'implémentation industrielle et professionnelle ultime pour votre système SAP S/4HANA (ABAP Pro).

Toute la logique de traitement a été externalisée dans une **classe globale standard (`ZCL_BP_CONTACT_HANDLER`)** gérée via la transaction **SE24** (ou Eclipse ADT). Les messages et textes retournés à l'utilisateur ou à CPI sont gérés via des **Symboles de texte (Text Symbols)** propres à la classe, garantissant un code propre sans chaînes de caractères en dur.

Le module de fonction RFC `ZRFC_BP_CONTACT_EQ1` instancie cette classe globale et lui délègue l'intégralité de l'exécution (Option A).

---

## 1. Contenu du Dossier `OO_Global`

Ce répertoire contient les fichiers suivants :

- **[`zcl_bp_contact_handler.clas.abap`](zcl_bp_contact_handler.clas.abap) :** Le code ABAP complet de la classe globale (sections d'interface et d'implémentation).
- **[`zcl_bp_contact_handler.clas.xml`](zcl_bp_contact_handler.clas.xml) :** Fichier de métadonnées XML (abapGit) décrivant la classe et recensant l'intégralité du pool de textes (**Text Symbols 001 à 020**) pour une saisie directe dans SAP.
- **[`zrfc_bp_contact_eq1_global.abap`](zrfc_bp_contact_eq1_global.abap) :** Le code du module de fonction (SE37) servant de wrapper d'appel vers la classe globale.

---

## 2. Procédure de Création Professionnelle dans SAP

### Étape 1 : Création de la Classe Globale (`SE24`)
1. Lancez la transaction **SE24**.
2. Saisissez le nom de la classe : `ZCL_BP_CONTACT_HANDLER` et cliquez sur **Créer**.
3. Dans la boîte de dialogue, choisissez :
   - *Class type* : **Usual ABAP Class**
   - *Scope* : **Public**
   - *Description* : `Gestionnaire de création de contacts BP (POO Globale)`
4. Allez dans l'onglet **Attributes** ou déclarez les constantes publiques (visibilité **Public**, type **Constant**) :

| Constante | Type associé | Valeur | Description |
| --- | --- | --- | --- |
| `CO_STATUS_SUCCESS` | `CHAR10` | `'SUCCESS'` | Statut de succès de traitement |
| `CO_STATUS_EXISTS` | `CHAR10` | `'EXISTS'` | Statut si le contact existe déjà |
| `CO_STATUS_LOCKED` | `CHAR10` | `'LOCKED'` | Statut de verrouillage concurrent |
| `CO_STATUS_ERROR` | `CHAR10` | `'ERROR'` | Statut d'erreur générale |
| `CO_BP_CATEGORY_PERSON` | `BU_TYPE` | `'1'` | Catégorie BP Personne |
| `CO_DEFAULT_GROUPING` | `BU_GROUP` | `'ZC'` | Regroupement par défaut |
| `CO_DEFAULT_ROLE` | `BU_PARTNERROLE` | `'BUP001'` | Rôle de contact par défaut |
| `CO_CONTACT_RELATION` | `BUT050-RELTYP` | `'BUR001'` | Type de relation de contact |
| `CO_DATE_TO_INFINITE` | `BUT050-DATE_TO` | `'99991231'` | Date de fin illimitée |

5. Copiez le code source du fichier [`zcl_bp_contact_handler.clas.abap`](zcl_bp_contact_handler.clas.abap) (en cliquant sur le bouton **Source Code** dans SE24 ou dans Eclipse ADT) et collez-le.

### Étape 2 : Configuration des Éléments de Texte (Text Symbols)
Pour éviter d'avoir des textes en dur dans le code (ce qui n'est pas professionnel), les messages d'erreur et de succès sont chargés dynamiquement via des symboles de texte.

1. Toujours dans la transaction **SE24** avec la classe `ZCL_BP_CONTACT_HANDLER`, allez dans le menu supérieur : **Saut (Goto) > Éléments de texte (Text Elements)**.
2. Saisissez les correspondances suivantes dans l'onglet **Text Symbols** :

| Symbole (Key) | Texte brut (Text) | Longueur max |
| --- | --- | --- |
| **`001`** | `BP parent, prénom et nom sont obligatoires.` | 50 |
| **`002`** | `La catégorie BP doit être 1 (Personne).` | 50 |
| **`003`** | `Le pays est obligatoire lorsqu'une adresse est fournie.` | 70 |
| **`004`** | `La date de début est invalide.` | 40 |
| **`005`** | `La date de fin est invalide.` | 40 |
| **`006`** | `La date de fin doit être postérieure ou égale à la date de début.` | 80 |
| **`007`** | `Le contact &1 existe déjà pour ce BP Parent.` | 60 |
| **`008`** | `Le BP Parent &1 n'existe pas.` | 40 |
| **`009`** | `Une création de contact est déjà en cours pour ce BP Parent. Réessayez ultérieurement.` | 100 |
| **`010`** | `Impossible de poser le verrou de création pour ce BP Parent.` | 70 |
| **`011`** | `Erreur inconnue lors de la création du BP.` | 60 |
| **`012`** | `Erreur de création du BP : &1` | 100 |
| **`013`** | `La création du BP n'a retourné aucun numéro de contact.` | 80 |
| **`014`** | `Erreur inconnue lors de l'ajout du rôle.` | 60 |
| **`015`** | `Erreur d'ajout du rôle : &1` | 100 |
| **`016`** | `Erreur inconnue lors du rattachement.` | 60 |
| **`017`** | `Erreur de création de la relation : &1` | 100 |
| **`018`** | `Erreur lors du commit : &1` | 100 |
| **`019`** | `Contact créé et rattaché au BP Parent &1.` | 70 |
| **`020`** | `Contact BP &1 créé et rattaché au BP Parent &2.` | 80 |

3. Enregistrez et activez les éléments de texte.

### Étape 3 : Création du Module de Fonction (`SE37`)
1. Créez la fonction `ZRFC_BP_CONTACT_EQ1` dans votre groupe de fonctions standard.
2. Configurez les attributs pour marquer la fonction comme **Remote-Enabled Module** (Lancement à distance).
3. Déclarez la signature exacte de l'interface en cochant impérativement la case **Passer valeur (Pass Value)** pour l'intégralité des paramètres d'importation, d'exportation et de modification (Changing).
4. Copiez et collez le code source du fichier [`zrfc_bp_contact_eq1_global.abap`](zrfc_bp_contact_eq1_global.abap).
5. Activez la fonction.

---

## 3. Synthèse de l'Architecture Technique Globale

```text
  [ Appel Distant CPI (JSON/XML) ]
                 │
                 ▼
  [ Module de Fonction : ZRFC_BP_CONTACT_EQ1 ] (SE37 - Remote-Enabled, Pass by Value)
                 │
                 ├─► Instancie lo_handler (Type REF TO ZCL_BP_CONTACT_HANDLER)
                 └─► Appelle lo_handler->execute( )
                               │
                               ▼
            [ Classe Globale : ZCL_BP_CONTACT_HANDLER ] (SE24 - ABAP Pro)
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
  [ Attributs Privés ]  [ Constantes Publiques ]  [ Éléments de Texte ]
  (Données & BAPIs)     (CO_STATUS_SUCCESS...)   (TEXT-001 à TEXT-020)
```
