*&---------------------------------------------------------------------*
*& Include LZFG_BP_CONTACT_EQ1F01
*&---------------------------------------------------------------------*

FORM add_return USING iv_type    TYPE bapiret2-type
                      iv_message TYPE bapi_msg
                CHANGING ct_return TYPE ztt_bapiret2.
  DATA ls_return TYPE bapiret2.

  ls_return-type    = iv_type.
  ls_return-message = iv_message.
  APPEND ls_return TO ct_return.
ENDFORM.

FORM set_error USING iv_message TYPE bapi_msg
               CHANGING cv_status  TYPE char10
                        cv_message TYPE bapi_msg
                        ct_return  TYPE ztt_bapiret2.
  cv_status  = gc_status_error.
  cv_message = iv_message.
  PERFORM add_return USING 'E' cv_message CHANGING ct_return.
ENDFORM.

FORM validate_request USING iv_bp_parent    TYPE bu_partner
                            iv_first_name    TYPE bu_namep_f
                            iv_last_name     TYPE bu_namep_l
                            iv_bp_category   TYPE bu_type
                            iv_street        TYPE ad_street
                            iv_house_number  TYPE ad_hsnm1
                            iv_postal_code   TYPE ad_pstcd1
                            iv_city          TYPE ad_city1
                            iv_country       TYPE land1
                            iv_region        TYPE regio
                      CHANGING cv_ok         TYPE abap_bool
                               cv_status     TYPE char10
                               cv_message    TYPE bapi_msg
                               ct_return     TYPE ztt_bapiret2.
  cv_ok = abap_false.

  IF iv_bp_parent IS INITIAL OR iv_first_name IS INITIAL OR iv_last_name IS INITIAL.
    PERFORM set_error USING 'BP parent, prénom et nom sont obligatoires.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  IF iv_bp_category IS NOT INITIAL AND iv_bp_category <> gc_bp_category_person.
    PERFORM set_error USING 'La catégorie BP doit être 1 (Personne).'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  IF ( iv_street IS NOT INITIAL OR iv_house_number IS NOT INITIAL
       OR iv_postal_code IS NOT INITIAL OR iv_city IS NOT INITIAL
       OR iv_region IS NOT INITIAL ) AND iv_country IS INITIAL.
    PERFORM set_error USING 'Le pays est obligatoire lorsqu''une adresse est fournie.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM resolve_validity USING iv_date_from TYPE dats
                            iv_date_to   TYPE dats
                      CHANGING cv_valid_from TYPE but050-date_from
                               cv_valid_to   TYPE but050-date_to
                               cv_ok         TYPE abap_bool
                               cv_status     TYPE char10
                               cv_message    TYPE bapi_msg
                               ct_return     TYPE ztt_bapiret2.
  cv_ok = abap_false.
  cv_valid_from = COND #( WHEN iv_date_from IS INITIAL THEN sy-datum ELSE iv_date_from ).
  cv_valid_to   = COND #( WHEN iv_date_to   IS INITIAL THEN gc_date_to_infinite ELSE iv_date_to ).

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date = cv_valid_from
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  IF sy-subrc <> 0.
    PERFORM set_error USING 'La date de début est invalide.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date = cv_valid_to
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  IF sy-subrc <> 0.
    PERFORM set_error USING 'La date de fin est invalide.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  IF cv_valid_to < cv_valid_from.
    PERFORM set_error USING 'La date de fin doit être postérieure ou égale à la date de début.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM check_parent_exists USING iv_bp_parent         TYPE bu_partner
                               iv_bp_parent_original TYPE bu_partner
                         CHANGING cv_ok              TYPE abap_bool
                                  cv_status          TYPE char10
                                  cv_message         TYPE bapi_msg
                                  ct_return          TYPE ztt_bapiret2.
  DATA lv_error_message TYPE bapi_msg.

  SELECT SINGLE partner
    FROM but000
    INTO @DATA(lv_parent_found)
    WHERE partner = @iv_bp_parent.

  IF sy-subrc <> 0.
    cv_ok = abap_false.
    lv_error_message = |Le BP Parent { iv_bp_parent_original } n'existe pas.|.
    PERFORM set_error USING lv_error_message
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM lock_parent_creation USING iv_bp_parent TYPE bu_partner
                          CHANGING cv_lock_key TYPE rstable-varkey
                                   cv_ok       TYPE abap_bool
                                   cv_status   TYPE char10
                                   cv_message  TYPE bapi_msg
                                   ct_return   TYPE ztt_bapiret2.
  cv_ok = abap_false.
  cv_lock_key = |{ sy-mandt }{ iv_bp_parent }|.

  CALL FUNCTION 'ENQUEUE_E_TABLE'
    EXPORTING
      tabname = 'BUT000'
      varkey  = cv_lock_key
      _scope  = '1'
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.

  IF sy-subrc = 1.
    cv_status  = gc_status_locked.
    cv_message = 'Une création de contact est déjà en cours pour ce BP Parent. Réessayez ultérieurement.'.
    PERFORM add_return USING 'E' cv_message CHANGING ct_return.
    RETURN.
  ENDIF.

  IF sy-subrc <> 0.
    PERFORM set_error USING 'Impossible de poser le verrou de création pour ce BP Parent.'
                      CHANGING cv_status cv_message ct_return.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM release_parent_lock USING iv_lock_key TYPE rstable-varkey.
  IF iv_lock_key IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DEQUEUE_E_TABLE'
    EXPORTING
      tabname = 'BUT000'
      varkey  = iv_lock_key
      _scope  = '1'.
ENDFORM.

FORM rollback_and_release USING iv_lock_key TYPE rstable-varkey.
  CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
  PERFORM release_parent_lock USING iv_lock_key.
ENDFORM.

FORM find_duplicate_contact USING iv_bp_parent  TYPE bu_partner
                                  iv_valid_from TYPE but050-date_from
                                  iv_valid_to   TYPE but050-date_to
                                  iv_first_name TYPE bu_namep_f
                                  iv_last_name  TYPE bu_namep_l
                            CHANGING cv_duplicate_id TYPE bu_partner.
  CLEAR cv_duplicate_id.
  SELECT SINGLE a~partner2
    FROM but050 AS a
    INNER JOIN but000 AS b ON b~partner = a~partner2
    INTO @cv_duplicate_id
    WHERE a~partner1   = @iv_bp_parent
      AND a~reltyp     = @gc_contact_relation
      AND a~date_from  <= @iv_valid_to
      AND a~date_to    >= @iv_valid_from
      AND b~name_first = @iv_first_name
      AND b~name_last  = @iv_last_name.
ENDFORM.

FORM prepare_contact_data USING iv_first_name   TYPE bu_namep_f
                                iv_last_name    TYPE bu_namep_l
                                iv_language     TYPE spras
                                iv_street       TYPE ad_street
                                iv_house_number TYPE ad_hsnm1
                                iv_postal_code  TYPE ad_pstcd1
                                iv_city         TYPE ad_city1
                                iv_country      TYPE land1
                                iv_region       TYPE regio
                                iv_bp_category  TYPE bu_type
                                iv_grouping     TYPE bu_group
                                iv_bp_role      TYPE bu_role
                          CHANGING cs_person_data     TYPE bapibus1006_central_person
                                   cs_central_data    TYPE bapibus1006_central
                                   cs_address_data    TYPE bapibus1006_address
                                   cv_partnercategory TYPE bu_type
                                   cv_partnergroup    TYPE bu_group
                                   cv_bp_role         TYPE bu_partnerrole.
  CLEAR: cs_person_data, cs_central_data, cs_address_data.

  cs_person_data-firstname           = iv_first_name.
  cs_person_data-lastname            = iv_last_name.
  cs_person_data-correspondlanguage  = iv_language.
  cs_address_data-street             = iv_street.
  cs_address_data-house_no           = iv_house_number.
  cs_address_data-postl_cod1         = iv_postal_code.
  cs_address_data-city               = iv_city.
  cs_address_data-country            = iv_country.
  cs_address_data-region             = iv_region.
  cv_partnercategory = COND #( WHEN iv_bp_category IS INITIAL THEN gc_bp_category_person ELSE iv_bp_category ).
  cv_partnergroup    = COND #( WHEN iv_grouping    IS INITIAL THEN gc_default_grouping ELSE iv_grouping ).
  cv_bp_role         = COND #( WHEN iv_bp_role     IS INITIAL THEN gc_default_role ELSE iv_bp_role ).
ENDFORM.

FORM evaluate_bapi_return TABLES it_return STRUCTURE bapiret2
                          CHANGING cv_failed       TYPE abap_bool
                                   cv_error_message TYPE bapi_msg
                                   ct_return        TYPE ztt_bapiret2.
  DATA ls_return TYPE bapiret2.

  CLEAR: cv_failed, cv_error_message.
  APPEND LINES OF it_return TO ct_return.
  LOOP AT it_return INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    cv_failed       = abap_true.
    cv_error_message = ls_return-message.
    EXIT.
  ENDLOOP.

  IF cv_failed = abap_true AND cv_error_message IS INITIAL.
    cv_error_message = 'Consultez CT_RETURN pour le détail BAPI.'.
  ENDIF.
ENDFORM.
