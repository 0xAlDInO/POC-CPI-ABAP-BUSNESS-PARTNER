# Création de contact via RFC — Version Orientée Objet (POO)

Ce dossier propose une variante de l'intégration RFC implémentée selon les standards modernes de la programmation orientée objet ABAP (ABAP OO).

L'intégralité de la logique d'orchestration, de validation, de gestion des verrous logiques, d'appels BAPIs et de gestion transactionnelle a été encapsulée dans une classe locale nommée `lcl_bp_contact_handler` (Option A de conception). Le module de fonction `ZRFC_BP_CONTACT_EQ1` agit comme un simple point d'entrée distant (passe-plat) qui instancie cette classe et lui délègue l'exécution.

## Avantages de la version POO (Option A)

- **Encapsulation & État d'instance :** Toutes les variables de travail, les structures d'adresses et les tables de retours sont gérées comme des attributs privés de la classe. Cela élimine le besoin de passer un nombre excessif de paramètres de routine en routine (ce qui arrivait avec les anciens `PERFORM ... USING ... CHANGING`).
- **Lisibilité accrue :** Les méthodes privées de la classe découpent le flux métier en étapes unitaires claires et documentées.
- **Robustesse accrue :** La gestion des exceptions et des retours BAPI est centralisée et standardisée au sein des méthodes de la classe.
- **Séparation des responsabilités :** Le module de fonction RFC gère uniquement l'interface externe et l'exposition réseau SAP, tandis que la classe locale assure la logique métier.

---

## 1. Structure Recommandée du Groupe de Fonctions

Pour installer cette version POO, créez ou modifiez un groupe de fonctions dédié (ex: `ZFG_BP_CONTACT_OO`).

Copiez ensuite les fichiers correspondants comme suit :

| Fichier SAP à créer | Source du dépôt | Rôle / Responsabilité |
| --- | --- | --- |
| **`LZFG_BP_CONTACT_OO_TOP`** | [`zfg_bp_contact_oo_top.abap`](zfg_bp_contact_oo_top.abap) | Déclarations des constantes globales, signature de la classe locale `lcl_bp_contact_handler`, attributs et déclaration de ses méthodes publiques et privées. |
| **`LZFG_BP_CONTACT_OO_F01`** | [`zfg_bp_contact_oo_f01.abap`](zfg_bp_contact_oo_f01.abap) | Implémentation complète des méthodes de la classe `lcl_bp_contact_handler` (méthode publique `execute` et méthodes privées). |
| **`ZRFC_BP_CONTACT_EQ1`** | [`zrfc_bp_contact_eq1_oo.abap`](zrfc_bp_contact_eq1_oo.abap) | Code du module de fonction (SE37) : instanciation de la classe et appel de `execute`. |

Dans le programme principal du groupe de fonctions (ex: `SAPLZFG_BP_CONTACT_OO`), assurez-vous d'inclure le fichier TOP :
```abap
FUNCTION-POOL zfg_bp_contact_oo.

INCLUDE lzfg_bp_contact_oo_top.
```

Le fichier `LZFG_BP_CONTACT_OO_TOP` charge lui-même l'implémentation à sa fin via l'instruction :
```abap
INCLUDE lzfg_bp_contact_oo_f01.
```

---

## 2. Configuration de l'Interface SE37

Lors de la création du module de fonction `ZRFC_BP_CONTACT_EQ1` dans la transaction **SE37**, configurez les attributs et paramètres comme suit.

### Onglet "Attributes"
- Cochez **Remote-Enabled Module** (pour permettre l'appel distant depuis CPI).

### Onglet "Import"
*Tous les paramètres d'importation doivent impérativement être passés par valeur (cochez la case **Passer valeur** / **Pass Value**) car les modules de fonction distants ne supportent pas le passage par référence.*

| Nom paramètre | Type associé | Optionnel | Passer valeur | Valeur par défaut |
| --- | --- | --- | --- | --- |
| `IV_BP_PARENT` | `BU_PARTNER` | Non | **Oui** | |
| `IV_FIRST_NAME` | `BU_NAMEP_F` | Non | **Oui** | |
| `IV_LAST_NAME` | `BU_NAMEP_L` | Non | **Oui** | |
| `IV_BP_CATEGORY` | `BU_TYPE` | Oui | **Oui** | `'1'` |
| `IV_GROUPING` | `BU_GROUP` | Oui | **Oui** | `'ZC'` |
| `IV_BP_ROLE` | `BU_PARTNERROLE` | Oui | **Oui** | `'BUP001'` |
| `IV_STREET` | `AD_STREET` | Oui | **Oui** | |
| `IV_HOUSE_NUMBER` | `AD_HSNM1` | Oui | **Oui** | |
| `IV_POSTAL_CODE` | `AD_PSTCD1` | Oui | **Oui** | |
| `IV_CITY` | `AD_CITY1` | Oui | **Oui** | |
| `IV_COUNTRY` | `LAND1` | Oui | **Oui** | |
| `IV_REGION` | `REGIO` | Oui | **Oui** | |
| `IV_LANGUAGE` | `SPRAS` | Oui | **Oui** | |
| `IV_DATE_FROM` | `DATS` | Oui | **Oui** | |
| `IV_DATE_TO` | `DATS` | Oui | **Oui** | |

### Onglet "Export"
*Cochez également la case **Passer valeur** pour tous les paramètres d'exportation.*

| Nom paramètre | Type associé | Passer valeur |
| --- | --- | --- |
| `EV_BP_CONTACT` | `BU_PARTNER` | **Oui** |
| `EV_STATUS_CODE` | `CHAR10` | **Oui** |
| `EV_STATUS_MESSAGE` | `BAPI_MSG` | **Oui** |

### Onglet "Changing"
*Cochez la case **Optionnel** et la case **Passer valeur**.*

| Nom paramètre | Type associé | Optionnel | Passer valeur |
| --- | --- | --- | --- |
| `CT_RETURN` | `ZTT_BAPIRET2` | **Oui** | **Oui** |

---

## 3. Ordre d'Activation SAP

Pour éviter toute erreur d'interdépendance lors de la compilation, activez les éléments dans l'ordre suivant :
1. L'include d'implémentation : `LZFG_BP_CONTACT_OO_F01`
2. L'include de définition : `LZFG_BP_CONTACT_OO_TOP`
3. Le module de fonction : `ZRFC_BP_CONTACT_EQ1`
4. Le groupe de fonctions global : `ZFG_BP_CONTACT_OO`
