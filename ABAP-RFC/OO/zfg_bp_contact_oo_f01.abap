*&---------------------------------------------------------------------*
*& Include LZFG_BP_CONTACT_OO_F01
*&---------------------------------------------------------------------*
*& Implémentation des méthodes de la classe locale lcl_bp_contact_handler
*&---------------------------------------------------------------------*

CLASS lcl_bp_contact_handler IMPLEMENTATION.

  METHOD execute.
    " Initialisation des exports et attributs
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

    " 3. Formatage de l'identifiant du BP Parent
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
      ev_status_code    = gc_status_exists.
      ev_status_message = |Le contact { mv_duplicate_id } existe déjà pour ce BP Parent.|.
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

    " 8. Création du BP Personne (BAPI)
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
      set_error( 'BP parent, prénom et nom sont obligatoires.' ).
      RETURN.
    ENDIF.

    IF iv_bp_category IS NOT INITIAL AND iv_bp_category <> gc_bp_category_person.
      set_error( 'La catégorie BP doit être 1 (Personne).' ).
      RETURN.
    ENDIF.

    IF ( iv_street IS NOT INITIAL OR iv_house_number IS NOT INITIAL
         OR iv_postal_code IS NOT INITIAL OR iv_city IS NOT INITIAL
         OR iv_region IS NOT INITIAL ) AND iv_country IS INITIAL.
      set_error( 'Le pays est obligatoire lorsqu''une adresse est fournie.' ).
      RETURN.
    ENDIF.

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD resolve_validity.
    rv_ok = abap_false.
    mv_valid_from = COND #( WHEN iv_date_from IS INITIAL THEN sy-datum ELSE iv_date_from ).
    mv_valid_to   = COND #( WHEN iv_date_to   IS INITIAL THEN gc_date_to_infinite ELSE iv_date_to ).

    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date = mv_valid_from
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc <> 0.
      set_error( 'La date de début est invalide.' ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date = mv_valid_to
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc <> 0.
      set_error( 'La date de fin est invalide.' ).
      RETURN.
    ENDIF.

    IF mv_valid_to < mv_valid_from.
      set_error( 'La date de fin doit être postérieure ou égale à la date de début.' ).
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
      lv_error_message = |Le BP Parent { iv_bp_parent_original } n'existe pas.|.
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
      mv_status_code  = gc_status_locked.
      mv_status_message = 'Une création de contact est déjà en cours pour ce BP Parent. Réessayez ultérieurement.'.
      add_return( iv_type    = 'E'
                  iv_message = mv_status_message ).
      RETURN.
    ENDIF.

    IF sy-subrc <> 0.
      set_error( 'Impossible de poser le verrou de création pour ce BP Parent.' ).
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
        AND a~reltyp     = @gc_contact_relation
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
    mv_partnercategory = COND #( WHEN iv_bp_category IS INITIAL THEN gc_bp_category_person ELSE iv_bp_category ).
    mv_partnergroup    = COND #( WHEN iv_grouping    IS INITIAL THEN gc_default_grouping ELSE iv_grouping ).
    mv_bp_role         = COND #( WHEN iv_bp_role     IS INITIAL THEN gc_default_role ELSE iv_bp_role ).
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
      " Récupération du message d'erreur s'il existe
      DATA ls_err TYPE bapiret2.
      READ TABLE lt_return_bapi INTO ls_err WITH KEY type = 'E'.
      IF sy-subrc = 0.
        lv_error_msg = ls_err-message.
      ELSE.
        lv_error_msg = 'Erreur inconnue lors de la création du BP.'.
      ENDIF.
      set_error( |Erreur de création du BP : { lv_error_msg }| ).
      RETURN.
    ENDIF.

    mv_bp_contact = mv_bp_contact_bapi.
    IF mv_bp_contact IS INITIAL.
      rollback_and_release( ).
      set_error( 'La création du BP n''a retourné aucun numéro de contact.' ).
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
        lv_error_msg = 'Erreur inconnue lors de l''ajout du rôle.'.
      ENDIF.
      set_error( |Erreur d'ajout du rôle : { lv_error_msg }| ).
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
        lv_error_msg = 'Erreur inconnue lors du rattachement.'.
      ENDIF.
      set_error( |Erreur de création de la relation : { lv_error_msg }| ).
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
      lv_error_msg = |Erreur lors du commit : { ls_commit_return-message }|.
      set_error( lv_error_msg ).
      RETURN.
    ENDIF.

    mv_status_code    = gc_status_success.
    mv_status_message = |Contact créé et rattaché au BP Parent { iv_bp_parent }.|.
    add_return( iv_type    = 'S'
                iv_message = |Contact BP { mv_bp_contact } créé et rattaché au BP Parent { iv_bp_parent }.| ).

    rv_ok = abap_true.
  ENDMETHOD.


  METHOD add_return.
    DATA ls_return TYPE bapiret2.
    ls_return-type    = iv_type.
    ls_return-message = iv_message.
    APPEND ls_return TO mt_return.
  ENDMETHOD.


  METHOD set_error.
    mv_status_code    = gc_status_error.
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
