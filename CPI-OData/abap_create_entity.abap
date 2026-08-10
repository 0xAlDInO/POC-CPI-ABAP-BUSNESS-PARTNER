*&---------------------------------------------------------------------*
*&  Class Implementation: ZCL_ZCONTACTS_DPC_EXT
*&  Method: CONTACTSET_CREATE_ENTITY
*&---------------------------------------------------------------------*
*&  Description : Permet de créer un Business Partner de type personne
*&                (catégorie 1), de lui affecter le rôle de contact (BUP001)
*&                et de créer une relation de type contact (BUR001) avec
*&                un Business Partner Parent (Client/Fournisseur).
*&---------------------------------------------------------------------*
METHOD contactset_create_entity.

  " Structures pour stocker les données d'entrée et de sortie OData
  DATA: ls_entry            TYPE zcl_zcontacts_mpc=>ts_contact,
        ls_response         TYPE zcl_zcontacts_mpc=>ts_contact.

  " Variables de travail pour les BAPIs
  DATA: lv_bp_parent        TYPE bu_partner,
        lv_bp_contact       TYPE bu_partner,
        ls_person_data      TYPE bapibus1006_central_person,
        ls_central_data     TYPE bapibus1006_central,
        ls_address_data     TYPE bapibus1006_address,
        lt_return_bapi      TYPE TABLE OF bapiret2,
        ls_return           TYPE bapiret2,
        lv_error            TYPE abap_bool VALUE abap_false,
        lv_error_msg        TYPE bapi_msg.

  " Lecture et décodage du payload d'entrée
  io_data_provider->read_entry_data( IMPORTING es_data = ls_entry ).

  " Paramètres BP par défaut pour préserver la compatibilité des appels existants
  IF ls_entry-bpcategory IS INITIAL.
    ls_entry-bpcategory = '1'. " 1 = Personne / Person
  ENDIF.
  IF ls_entry-grouping IS INITIAL.
    ls_entry-grouping = 'ZC'. " Groupement pour plage de numéros interne
  ENDIF.
  IF ls_entry-bprole IS INITIAL.
    ls_entry-bprole = 'BUP001'. " Contact Person Role
  ENDIF.

  " Copie initiale de l'entrée vers la réponse
  ls_response = ls_entry.

  " ---------------------------------------------------------------------
  " ETAPE 1 : Validation de l'existence du BP Parent
  " ---------------------------------------------------------------------
  " Formatage du numéro de BP parent (ajout de zéros non significatifs)
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING
      input  = ls_entry-bpparent
    IMPORTING
      output = lv_bp_parent.

  " Vérification dans la table BUT000
  SELECT SINGLE partner, type FROM but000
    INTO @DATA(ls_parent_chk)
    WHERE partner = @lv_bp_parent.

  IF sy-subrc <> 0.
    ls_response-statuscode    = 'ERROR'.
    ls_response-statusmessage = |Le BP Parent { ls_entry-bpparent } n'existe pas dans le système SAP.|.
    er_entity = ls_response.
    RETURN.
  ENDIF.

  " ---------------------------------------------------------------------
  " ETAPE 2 : Détection des doublons de contact rattachés à ce BP parent
  " ---------------------------------------------------------------------
  " Un doublon est défini par : même Prénom, même Nom rattaché au même BP Parent
  " via une relation active dans BUT050
  SELECT SINGLE a~partner2
    FROM but050 AS a
    INNER JOIN but000 AS b ON a~partner2 = b~partner
    INTO @DATA(lv_duplicate_id)
    WHERE a~partner1   = @lv_bp_parent
      AND a~reltyp     = 'BUR001' " Relation de contact
      AND a~date_from  <= @sy-datum
      AND a~date_to    >= @sy-datum
      AND b~name_first = @ls_entry-firstname
      AND b~name_last  = @ls_entry-lastname.

  IF sy-subrc = 0.
    " Un doublon actif a été trouvé !
    " On récupère l'ID existant et on retourne un code spécifique
    ls_response-bpcontactid   = lv_duplicate_id.
    ls_response-statuscode    = 'EXISTS'.
    ls_response-statusmessage = |Un contact similaire (ID: { lv_duplicate_id }) existe déjà pour ce BP Parent.|.
    er_entity = ls_response.
    RETURN.
  ENDIF.

  " ---------------------------------------------------------------------
  " ETAPE 3 : Préparation des données pour la création du BP (BAPI)
  " ---------------------------------------------------------------------
  " Données de la Personne (BUT000)
  ls_person_data-firstname = ls_entry-firstname.
  ls_person_data-lastname  = ls_entry-lastname.

  " Données d'en-tête centrales (Regroupement)
  ls_central_data-partn_grp = ls_entry-grouping.

  " Données d'Adresse (ADRC)
  ls_address_data-street     = ls_entry-street.
  ls_address_data-house_no   = ls_entry-housenumber.
  ls_address_data-postl_cod1 = ls_entry-postalcode.
  ls_address_data-city       = ls_entry-city.
  ls_address_data-country    = ls_entry-country.
  ls_address_data-region     = ls_entry-region.
  ls_address_data-langu      = ls_entry-language.

  " ---------------------------------------------------------------------
  " ETAPE 4 : Appel de BAPI_BUPA_CREATE_FROM_DATA
  " ---------------------------------------------------------------------
  CALL FUNCTION 'BAPI_BUPA_CREATE_FROM_DATA'
    EXPORTING
      partnercategory    = ls_entry-bpcategory
      centraldata        = ls_central_data
      centraldataperson  = ls_person_data
      addressdata        = ls_address_data
    IMPORTING
      businesspartner = lv_bp_contact
    TABLES
      return          = lt_return_bapi.

  " Vérification s'il y a des erreurs bloquantes (Type E, A ou X)
  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_error     = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.

  IF lv_error = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ls_response-statuscode    = 'ERROR'.
    ls_response-statusmessage = |Erreur lors de la création du BP: { lv_error_msg }|.
    er_entity = ls_response.
    RETURN.
  ENDIF.

  " ---------------------------------------------------------------------
  " ETAPE 5 : Ajout du Rôle de Personne de Contact (BUP001)
  " ---------------------------------------------------------------------
  CLEAR lt_return_bapi.
  CALL FUNCTION 'BAPI_BUPA_ROLE_ADD_2'
    EXPORTING
      businesspartner = lv_bp_contact
      businesspartnerrole = ls_entry-bprole
    TABLES
      return          = lt_return_bapi.

  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_error     = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.

  IF lv_error = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ls_response-statuscode    = 'ERROR'.
    ls_response-statusmessage = |Erreur lors de l'ajout du rôle BUP001: { lv_error_msg }|.
    er_entity = ls_response.
    RETURN.
  ENDIF.

  " ---------------------------------------------------------------------
  " ETAPE 6 : Création de la Relation avec le BP Parent (BUR001)
  " ---------------------------------------------------------------------
  CLEAR lt_return_bapi.

  " Détermination des dates de validité de la relation
  DATA: lv_valid_from TYPE but050-date_from,
        lv_valid_to   TYPE but050-date_to.

  IF ls_entry-datefrom IS INITIAL.
    lv_valid_from = sy-datum. " Par défaut : Aujourd'hui
  ELSE.
    " Conversion du format DateTime OData en format de date SAP (YYYYMMDD)
    lv_valid_from = ls_entry-datefrom(8).
  ENDIF.

  IF ls_entry-dateto IS INITIAL.
    lv_valid_to = '99991231'. " Par défaut : Illimitée
  ELSE.
    lv_valid_to = ls_entry-dateto(8).
  ENDIF.

  CALL FUNCTION 'BAPI_BUPR_CONTP_CREATE'
    EXPORTING
      businesspartner = lv_bp_parent  " BP Parent (Client/Fournisseur - Organisation)
      contactperson   = lv_bp_contact " BP Enfant (Contact - Personne)
      validfromdate   = lv_valid_from
      validuntildate  = lv_valid_to
    TABLES
      return          = lt_return_bapi.

  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_error     = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.

  IF lv_error = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ls_response-statuscode    = 'ERROR'.
    ls_response-statusmessage = |Erreur lors de la création de la relation de contact (BUR001): { lv_error_msg }|.
    er_entity = ls_response.
    RETURN.
  ENDIF.

  " ---------------------------------------------------------------------
  " ETAPE 7 : Validation Transactionnelle (COMMIT) et réponse
  " ---------------------------------------------------------------------
  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait = 'X'.

  " Retrait du format interne (suppression des zéros pour la réponse propre)
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
    EXPORTING
      input  = lv_bp_contact
    IMPORTING
      output = ls_response-bpcontactid.

  ls_response-statuscode    = 'SUCCESS'.
  ls_response-statusmessage = |Le contact a été créé avec succès et lié au BP Parent { ls_entry-bpparent }.|.

  " Retourner l'entité créée à SAP Gateway
  er_entity = ls_response.

ENDMETHOD.
