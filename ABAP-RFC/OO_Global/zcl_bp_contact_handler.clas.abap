CLASS zcl_bp_contact_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " Constantes publiques (Professionnel / SE24 Attributes)
    CONSTANTS:
      co_status_success     TYPE char10          VALUE 'SUCCESS',
      co_status_exists      TYPE char10          VALUE 'EXISTS',
      co_status_locked      TYPE char10          VALUE 'LOCKED',
      co_status_error       TYPE char10          VALUE 'ERROR',
      co_bp_category_person TYPE bu_type         VALUE '1',
      co_default_grouping   TYPE bu_group        VALUE 'ZC',
      co_default_role       TYPE bu_partnerrole  VALUE 'BUP001',
      co_contact_relation   TYPE but050-reltyp   VALUE 'BUR001',
      co_date_to_infinite   TYPE but050-date_to  VALUE '99991231'.

    METHODS execute
      IMPORTING
        !iv_bp_parent      TYPE bu_partner
        !iv_first_name     TYPE bu_namep_f
        !iv_last_name      TYPE bu_namep_l
        !iv_bp_category    TYPE bu_type
        !iv_grouping       TYPE bu_group
        !iv_bp_role        TYPE bu_role
        !iv_date_from      TYPE dats
        !iv_date_to        TYPE dats
        !iv_street         TYPE ad_street
        !iv_house_number   TYPE ad_hsnm1
        !iv_postal_code    TYPE ad_pstcd1
        !iv_city           TYPE ad_city1
        !iv_country        TYPE land1
        !iv_region         TYPE regio
        !iv_language       TYPE spras
      EXPORTING
        !ev_bp_contact     TYPE bu_partner
        !ev_status_code    TYPE char10
        !ev_status_message TYPE bapi_msg
        !ct_return         TYPE ztt_bapiret2 .

  PROTECTED SECTION.
  PRIVATE SECTION.
    " Variables d'état de l'instance
    DATA mv_bp_parent        TYPE bu_partner .
    DATA mv_bp_contact       TYPE bu_partner .
    DATA mv_bp_contact_bapi  TYPE bapibus1006_head-bpartner .
    DATA mv_valid_from       TYPE but050-date_from .
    DATA mv_valid_to         TYPE but050-date_to .
    DATA mv_duplicate_id     TYPE bu_partner .
    DATA mv_parent_lock_key  TYPE rstable-varkey .
    DATA mv_status_code      TYPE char10 .
    DATA mv_status_message   TYPE bapi_msg .
    DATA mt_return           TYPE ztt_bapiret2 .
    DATA ms_person_data      TYPE bapibus1006_central_person .
    DATA ms_central_data     TYPE bapibus1006_central .
    DATA ms_address_data     TYPE bapibus1006_address .
    DATA mv_partnercategory  TYPE bu_type .
    DATA mv_partnergroup     TYPE bu_group .
    DATA mv_bp_role          TYPE bu_partnerrole .

    METHODS validate_request
      IMPORTING
        !iv_bp_parent    TYPE bu_partner
        !iv_first_name   TYPE bu_namep_f
        !iv_last_name    TYPE bu_namep_l
        !iv_bp_category  TYPE bu_type
        !iv_street       TYPE ad_street
        !iv_house_number TYPE ad_hsnm1
        !iv_postal_code  TYPE ad_pstcd1
        !iv_city         TYPE ad_city1
        !iv_country      TYPE land1
        !iv_region       TYPE regio
      RETURNING
        VALUE(rv_ok)     TYPE abap_bool .

    METHODS resolve_validity
      IMPORTING
        !iv_date_from TYPE dats
        !iv_date_to   TYPE dats
      RETURNING
        VALUE(rv_ok)  TYPE abap_bool .

    METHODS check_parent_exists
      IMPORTING
        !iv_bp_parent_original TYPE bu_partner
      RETURNING
        VALUE(rv_ok)           TYPE abap_bool .

    METHODS lock_parent_creation
      RETURNING
        VALUE(rv_ok) TYPE abap_bool .

    METHODS find_duplicate_contact
      IMPORTING
        !iv_first_name TYPE bu_namep_f
        !iv_last_name  TYPE bu_namep_l .

    METHODS prepare_contact_data
      IMPORTING
        !iv_first_name   TYPE bu_namep_f
        !iv_last_name    TYPE bu_namep_l
        !iv_language     TYPE spras
        !iv_street       TYPE ad_street
        !iv_house_number TYPE ad_hsnm1
        !iv_postal_code  TYPE ad_pstcd1
        !iv_city         TYPE ad_city1
        !iv_country      TYPE land1
        !iv_region       TYPE regio
        !iv_bp_category  TYPE bu_type
        !iv_grouping     TYPE bu_group
        !iv_bp_role      TYPE bu_role .

    METHODS create_bp_person
      RETURNING
        VALUE(rv_ok) TYPE abap_bool .

    METHODS add_bp_role
      RETURNING
        VALUE(rv_ok) TYPE abap_bool .

    METHODS create_bp_relation
      RETURNING
        VALUE(rv_ok) TYPE abap_bool .

    METHODS commit_transaction
      IMPORTING
        !iv_bp_parent TYPE bu_partner
      RETURNING
        VALUE(rv_ok)  TYPE abap_bool .

    METHODS release_parent_lock .

    METHODS rollback_and_release .

    METHODS add_return
      IMPORTING
        !iv_type    TYPE bapiret2-type
        !iv_message TYPE bapi_msg .

    METHODS set_error
      IMPORTING
        !iv_message TYPE bapi_msg .

    METHODS evaluate_bapi_return
      IMPORTING
        !it_return_bapi TYPE bapiret2_tab
      RETURNING
        VALUE(rv_failed) TYPE abap_bool .
ENDCLASS.



CLASS zcl_bp_contact_handler IMPLEMENTATION.


  METHOD execute.
    " Initialisation
    CLEAR: ev_bp_contact, ev_status_code, ev_status_message, ct_return.
    CLEAR: mv_bp_parent, mv_bp_contact, mv_bp_contact_bapi, mv_valid_from, mv_valid_to,
           mv_duplicate_id, mv_parent_lock_key, mv_status_code, mv_status_message, mt_return,
           ms_person_data, ms_central_data, ms_address_data, mv_partnercategory, mv_partnergroup, mv_bp_role.

    " 1. Validation de la requête
    IF validate_request( iv_bp_parent    = iv_bp_parent
                         iv_first_name   = iv_first_name
                         iv_last_name    = iv_last_name
                         iv_bp_category  = iv_bp_category
                         iv_street       = iv_street
                         iv_house_number = iv_house_number
                         iv_postal_code  = iv_postal_code
                         iv_city         = iv_city
                         iv_country      = iv_country
                         iv_region       = iv_region ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 2. Résolution des dates de validité
    IF resolve_validity( iv_date_from = iv_date_from
                         iv_date_to   = iv_date_to ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 3. Formatage de l'identifiant du BP Parent (CONVERSION_EXIT_ALPHA_INPUT)
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = iv_bp_parent
      IMPORTING
        output = mv_bp_parent.

    " 4. Vérification que le BP Parent existe
    IF check_parent_exists( iv_bp_parent_original = iv_bp_parent ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 5. Pose d'un verrou sur le BP Parent
    IF lock_parent_creation( ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 6. Recherche de doublons
    find_duplicate_contact( iv_first_name = iv_first_name
                            iv_last_name  = iv_last_name ).
    IF mv_duplicate_id IS NOT INITIAL.
      release_parent_lock( ).
      ev_bp_contact     = mv_duplicate_id.
      ev_status_code    = co_status_exists.
      " Récupération du texte d'erreur via Text Symbol (TEXT-007)
      " 'Le contact &1 existe déjà pour ce BP Parent.'
      ev_status_message = TEXT-007.
      REPLACE '&1' IN ev_status_message WITH mv_duplicate_id.
      IF sy-subrc <> 0.
        ev_status_message = |Le contact { mv_duplicate_id } existe déjà pour ce BP Parent.|.
      ENDIF.
      add_return( iv_type    = 'S'
                  iv_message = ev_status_message ).
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 7. Préparation des données d'adresse et d'identité
    prepare_contact_data( iv_first_name   = iv_first_name
                          iv_last_name    = iv_last_name
                          iv_language     = iv_language
                          iv_street       = iv_street
                          iv_house_number = iv_house_number
                          iv_postal_code  = iv_postal_code
                          iv_city         = iv_city
                          iv_country      = iv_country
                          iv_region       = iv_region
                          iv_bp_category  = iv_bp_category
                          iv_grouping     = iv_grouping
                          iv_bp_role      = iv_bp_role ).

    " 8. Création du BP Personne (BAPI_BUPA_CREATE_FROM_DATA)
    IF create_bp_person( ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 9. Ajout du rôle Contact Person (BUP001)
    IF add_bp_role( ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 10. Rattachement au parent (BAPI_BUPR_CONTP_CREATE)
    IF create_bp_relation( ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " 11. Validation finale (Commit)
    IF commit_transaction( iv_bp_parent = iv_bp_parent ) = abap_false.
      ev_status_code    = mv_status_code.
      ev_status_message = mv_status_message.
      ct_return         = mt_return.
      RETURN.
    ENDIF.

    " Retour de succès
    ev_bp_contact     = mv_bp_contact.
    ev_status_code    = mv_status_code.
    ev_status_message = mv_status_message.
    ct_return         = mt_return.
  ENDMETHOD.


  METHOD validate_request.
    rv_ok = abap_false.

    IF iv_bp_parent IS INITIAL OR iv_first_name IS INITIAL OR iv_last_name IS INITIAL.
      " TEXT-001 : 'BP parent, prénom et nom sont obligatoires.'
      set_error( TEXT-001 ).
      RETURN.
    ENDIF.

    IF iv_bp_category IS NOT INITIAL AND iv_bp_category <> co_bp_category_person.
      " TEXT-002 : 'La catégorie BP doit être 1 (Personne).'
      set_error( TEXT-002 ).
      RETURN.
    ENDIF.

    IF ( iv_street IS NOT INITIAL OR iv_house_number IS NOT INITIAL
         OR iv_postal_code IS NOT INITIAL OR iv_city IS NOT INITIAL
         OR iv_region IS NOT INITIAL ) AND iv_country IS INITIAL.
      " TEXT-003 : 'Le pays est obligatoire lorsqu''une adresse est fournie.'
      set_error( TEXT-003 ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD resolve_validity.
    rv_ok = abap_false.
    mv_valid_from = COND #( WHEN iv_date_from IS INITIAL THEN sy-datum ELSE iv_date_from ).
    mv_valid_to   = COND #( WHEN iv_date_to   IS INITIAL THEN co_date_to_infinite ELSE iv_date_to ).

    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date = mv_valid_from
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc <> 0.
      " TEXT-004 : 'La date de début est invalide.'
      set_error( TEXT-004 ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date = mv_valid_to
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc <> 0.
      " TEXT-005 : 'La date de fin est invalide.'
      set_error( TEXT-005 ).
      RETURN.
    ENDIF.

    IF mv_valid_to < mv_valid_from.
      " TEXT-006 : 'La date de fin doit être postérieure ou égale à la date de début.'
      set_error( TEXT-006 ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD check_parent_exists.
    rv_ok = abap_false.
    DATA lv_error_message TYPE bapi_msg.
    DATA lv_parent_found TYPE bu_partner.

    SELECT SINGLE partner
      FROM but000
      INTO @lv_parent_found
      WHERE partner = @mv_bp_parent.

    IF sy-subrc <> 0.
      " TEXT-008 : 'Le BP Parent &1 n''existe pas.'
      lv_error_message = TEXT-008.
      REPLACE '&1' IN lv_error_message WITH iv_bp_parent_original.
      IF sy-subrc <> 0.
        lv_error_message = |Le BP Parent { iv_bp_parent_original } n'existe pas.|.
      ENDIF.
      set_error( lv_error_message ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD lock_parent_creation.
    rv_ok = abap_false.
    mv_parent_lock_key = |{ sy-mandt }{ mv_bp_parent }|.

    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = mv_parent_lock_key
        _scope  = '1'
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    IF sy-subrc = 1.
      mv_status_code  = co_status_locked.
      " TEXT-009 : 'Une création de contact est déjà en cours pour ce BP Parent. Réessayez ultérieurement.'
      mv_status_message = TEXT-009.
      add_return( iv_type    = 'E'
                  iv_message = mv_status_message ).
      RETURN.
    ENDIF.

    IF sy-subrc <> 0.
      " TEXT-010 : 'Impossible de poser le verrou de création pour ce BP Parent.'
      set_error( TEXT-010 ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD release_parent_lock.
    IF mv_parent_lock_key IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = mv_parent_lock_key
        _scope  = '1'.
  ENDMETHOD.


  METHOD rollback_and_release.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    release_parent_lock( ).
  ENDMETHOD.


  METHOD find_duplicate_contact.
    CLEAR mv_duplicate_id.
    SELECT SINGLE a~partner2
      FROM but050 AS a
      INNER JOIN but000 AS b ON b~partner = a~partner2
      INTO @mv_duplicate_id
      WHERE a~partner1   = @mv_bp_parent
        AND a~reltyp     = @co_contact_relation
        AND a~date_from  <= @mv_valid_to
        AND a~date_to    >= @mv_valid_from
        AND b~name_first = @iv_first_name
        AND b~name_last  = @iv_last_name.
  ENDMETHOD.


  METHOD prepare_contact_data.
    CLEAR: ms_person_data, ms_central_data, ms_address_data.

    ms_person_data-firstname           = iv_first_name.
    ms_person_data-lastname            = iv_last_name.
    ms_person_data-correspondlanguage  = iv_language.
    ms_address_data-street             = iv_street.
    ms_address_data-house_no           = iv_house_number.
    ms_address_data-postl_cod1         = iv_postal_code.
    ms_address_data-city               = iv_city.
    ms_address_data-country            = iv_country.
    ms_address_data-region             = iv_region.
    mv_partnercategory = COND #( WHEN iv_bp_category IS INITIAL THEN co_bp_category_person ELSE iv_bp_category ).
    mv_partnergroup    = COND #( WHEN iv_grouping    IS INITIAL THEN co_default_grouping ELSE iv_grouping ).
    mv_bp_role         = COND #( WHEN iv_bp_role     IS INITIAL THEN co_default_role ELSE iv_bp_role ).
  ENDMETHOD.


  METHOD create_bp_person.
    rv_ok = abap_false.
    DATA: lt_return_bapi TYPE STANDARD TABLE OF bapiret2,
          lv_error_msg   TYPE bapi_msg.

    CALL FUNCTION 'BAPI_BUPA_CREATE_FROM_DATA'
      EXPORTING
        partnercategory   = mv_partnercategory
        partnergroup      = mv_partnergroup
        centraldata       = ms_central_data
        centraldataperson = ms_person_data
        addressdata       = ms_address_data
      IMPORTING
        businesspartner   = mv_bp_contact_bapi
      TABLES
        return            = lt_return_bapi.

    IF evaluate_bapi_return( lt_return_bapi ) = abap_true.
      rollback_and_release( ).
      DATA ls_err TYPE bapiret2.
      READ TABLE lt_return_bapi INTO ls_err WITH KEY type = 'E'.
      IF sy-subrc = 0.
        lv_error_msg = ls_err-message.
      ELSE.
        " TEXT-011 : 'Erreur inconnue lors de la création du BP.'
        lv_error_msg = TEXT-011.
      ENDIF.
      " TEXT-012 : 'Erreur de création du BP : &1'
      DATA lv_final_msg TYPE string.
      lv_final_msg = TEXT-012.
      REPLACE '&1' IN lv_final_msg WITH lv_error_msg.
      IF sy-subrc <> 0.
        lv_final_msg = |Erreur de création du BP : { lv_error_msg }|.
      ENDIF.
      set_error( lv_final_msg ).
      RETURN.
    ENDIF.

    mv_bp_contact = mv_bp_contact_bapi.
    IF mv_bp_contact IS INITIAL.
      rollback_and_release( ).
      " TEXT-013 : 'La création du BP n''a retourné aucun numéro de contact.'
      set_error( TEXT-013 ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD add_bp_role.
    rv_ok = abap_false.
    DATA: lt_return_bapi TYPE STANDARD TABLE OF bapiret2,
          lv_error_msg   TYPE bapi_msg.

    CALL FUNCTION 'BAPI_BUPA_ROLE_ADD_2'
      EXPORTING
        businesspartner     = mv_bp_contact
        businesspartnerrole = mv_bp_role
      TABLES
        return              = lt_return_bapi.

    IF evaluate_bapi_return( lt_return_bapi ) = abap_true.
      rollback_and_release( ).
      DATA ls_err TYPE bapiret2.
      READ TABLE lt_return_bapi INTO ls_err WITH KEY type = 'E'.
      IF sy-subrc = 0.
        lv_error_msg = ls_err-message.
      ELSE.
        " TEXT-014 : 'Erreur inconnue lors de l''ajout du rôle.'
        lv_error_msg = TEXT-014.
      ENDIF.
      " TEXT-015 : 'Erreur d''ajout du rôle : &1'
      DATA lv_final_msg TYPE string.
      lv_final_msg = TEXT-015.
      REPLACE '&1' IN lv_final_msg WITH lv_error_msg.
      IF sy-subrc <> 0.
        lv_final_msg = |Erreur d'ajout du rôle : { lv_error_msg }|.
      ENDIF.
      set_error( lv_final_msg ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD create_bp_relation.
    rv_ok = abap_false.
    DATA: lt_return_bapi TYPE STANDARD TABLE OF bapiret2,
          lv_error_msg   TYPE bapi_msg.

    CALL FUNCTION 'BAPI_BUPR_CONTP_CREATE'
      EXPORTING
        businesspartner = mv_bp_parent
        contactperson   = mv_bp_contact
        validfromdate   = mv_valid_from
        validuntildate  = mv_valid_to
      TABLES
        return          = lt_return_bapi.

    IF evaluate_bapi_return( lt_return_bapi ) = abap_true.
      rollback_and_release( ).
      DATA ls_err TYPE bapiret2.
      READ TABLE lt_return_bapi INTO ls_err WITH KEY type = 'E'.
      IF sy-subrc = 0.
        lv_error_msg = ls_err-message.
      ELSE.
        " TEXT-016 : 'Erreur inconnue lors du rattachement.'
        lv_error_msg = TEXT-016.
      ENDIF.
      " TEXT-017 : 'Erreur de création de la relation : &1'
      DATA lv_final_msg TYPE string.
      lv_final_msg = TEXT-017.
      REPLACE '&1' IN lv_final_msg WITH lv_error_msg.
      IF sy-subrc <> 0.
        lv_final_msg = |Erreur de création de la relation : { lv_error_msg }|.
      ENDIF.
      set_error( lv_final_msg ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD commit_transaction.
    rv_ok = abap_false.
    DATA: ls_commit_return TYPE bapiret2,
          lv_error_msg     TYPE bapi_msg.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait   = abap_true
      IMPORTING
        return = ls_commit_return.

    IF ls_commit_return-type IS NOT INITIAL OR ls_commit_return-message IS NOT INITIAL.
      APPEND ls_commit_return TO mt_return.
    ENDIF.
    release_parent_lock( ).

    IF ls_commit_return-type = 'E' OR ls_commit_return-type = 'A'
       OR ls_commit_return-type = 'X'.
      CLEAR mv_bp_contact.
      " TEXT-018 : 'Erreur lors du commit : &1'
      lv_error_msg = TEXT-018.
      REPLACE '&1' IN lv_error_msg WITH ls_commit_return-message.
      IF sy-subrc <> 0.
        lv_error_msg = |Erreur lors du commit : { ls_commit_return-message }|.
      ENDIF.
      set_error( lv_error_msg ).
      RETURN.
    ENDIF.

    mv_status_code    = co_status_success.
    " TEXT-019 : 'Contact créé et rattaché au BP Parent &1.'
    mv_status_message = TEXT-019.
    REPLACE '&1' IN mv_status_message WITH iv_bp_parent.
    IF sy-subrc <> 0.
      mv_status_message = |Contact créé et rattaché au BP Parent { iv_bp_parent }.|.
    ENDIF.

    " TEXT-020 : 'Contact BP &1 créé et rattaché au BP Parent &2.'
    DATA lv_success_log TYPE string.
    lv_success_log = TEXT-020.
    REPLACE '&1' IN lv_success_log WITH mv_bp_contact.
    REPLACE '&2' IN lv_success_log WITH iv_bp_parent.
    IF sy-subrc <> 0.
      lv_success_log = |Contact BP { mv_bp_contact } créé et rattaché au BP Parent { iv_bp_parent }.|.
    ENDIF.

    add_return( iv_type    = 'S'
                iv_message = lv_success_log ).

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD add_return.
    DATA ls_return TYPE bapiret2.
    ls_return-type    = iv_type.
    ls_return-message = iv_message.
    APPEND ls_return TO mt_return.
  ENDMETHOD.


  METHOD set_error.
    mv_status_code    = co_status_error.
    mv_status_message = iv_message.
    add_return( iv_type    = 'E'
                iv_message = mv_status_message ).
  ENDMETHOD.


  METHOD evaluate_bapi_return.
    DATA ls_return TYPE bapiret2.
    rv_failed = abap_false.

    APPEND LINES OF it_return_bapi TO mt_return.
    LOOP AT it_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
      rv_failed = abap_true.
      EXIT.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
