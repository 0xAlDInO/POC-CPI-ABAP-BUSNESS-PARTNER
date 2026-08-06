*&---------------------------------------------------------------------*
*& Function Module : ZRFC_BP_CONTACT_EQ1
*& Remote-Enabled : Yes (SE37 > Attributes > Remote-Enabled Module)
*&---------------------------------------------------------------------*
*& Create the interface below in SE37, then paste the implementation.
*&
*& IMPORTING
*&   IV_BP_PARENT   TYPE BU_PARTNER
*&   IV_FIRST_NAME  TYPE BU_NAMEP_F
*&   IV_LAST_NAME   TYPE BU_NAMEP_L
*&   IV_BP_CATEGORY TYPE BU_TYPE           DEFAULT '1'
*&   IV_GROUPING    TYPE BU_GROUP          DEFAULT 'ZC'
*&   IV_BP_ROLE     TYPE BU_PARTNERROLE    DEFAULT 'BUP001'
*&   IV_STREET      TYPE AD_STREET         OPTIONAL
*&   IV_HOUSE_NUMBER TYPE AD_HSNM1         OPTIONAL
*&   IV_POSTAL_CODE TYPE AD_PSTCD1         OPTIONAL
*&   IV_CITY        TYPE AD_CITY1          OPTIONAL
*&   IV_COUNTRY     TYPE LAND1             OPTIONAL
*&   IV_REGION      TYPE REGIO             OPTIONAL
*&   IV_LANGUAGE    TYPE SPRAS             OPTIONAL
*&   IV_DATE_FROM   TYPE DATS              OPTIONAL
*&   IV_DATE_TO     TYPE DATS              OPTIONAL
*& EXPORTING
*&   EV_BP_CONTACT    TYPE BU_PARTNER
*&   EV_STATUS_CODE   TYPE CHAR10
*&   EV_STATUS_MESSAGE TYPE BAPI_MSG
*& CHANGING
*&   CT_RETURN TYPE ZTT_BAPIRET2 OPTIONAL
*&---------------------------------------------------------------------*
FUNCTION zrfc_bp_contact_eq1.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     REFERENCE(IV_BP_PARENT) TYPE  BU_PARTNER
*"     REFERENCE(IV_FIRST_NAME) TYPE  BU_NAMEP_F
*"     REFERENCE(IV_LAST_NAME) TYPE  BU_NAMEP_L
*"     REFERENCE(IV_BP_CATEGORY) TYPE  BU_TYPE
*"     REFERENCE(IV_GROUPING) TYPE  BU_GROUP
*"     REFERENCE(IV_BP_ROLE) TYPE  BU_ROLE
*"     REFERENCE(IV_DATE_FROM) TYPE  DATS
*"     REFERENCE(IV_DATE_TO) TYPE  DATS
*"     REFERENCE(IV_STREET) TYPE  AD_STREET
*"     REFERENCE(IV_HOUSE_NUMBER) TYPE  AD_HSNM1
*"     REFERENCE(IV_POSTAL_CODE) TYPE  AD_PSTCD1
*"     REFERENCE(IV_CITY) TYPE  AD_CITY1
*"     REFERENCE(IV_COUNTRY) TYPE  LAND1
*"     REFERENCE(IV_REGION) TYPE  REGIO
*"     REFERENCE(IV_LANGUAGE) TYPE  SPRAS
*"  EXPORTING
*"     REFERENCE(EV_BP_CONTACT) TYPE  BU_PARTNER
*"     REFERENCE(EV_STATUS_CODE) TYPE  CHAR10
*"     REFERENCE(EV_STATUS_MESSAGE) TYPE  BAPI_MSG
*"  CHANGING
*"     REFERENCE(CT_RETURN) TYPE  ZTT_BAPIRET2
*"----------------------------------------------------------------------

  DATA: lv_bp_parent       TYPE bu_partner,
        lv_bp_contact      TYPE bu_partner,
        lv_bp_contact_bapi TYPE bapibus1006_head-bpartner,
        lv_valid_from      TYPE but050-date_from,
        lv_valid_to        TYPE but050-date_to,
        lv_duplicate_id    TYPE bu_partner,
        lv_error_msg       TYPE bapi_msg,
        lv_bapi_failed     TYPE abap_bool,
        lv_partnercategory TYPE bu_type,
        lv_partnergroup    TYPE bu_group,
        lv_bp_role         TYPE bu_partnerrole,
        lv_parent_lock_key TYPE rstable-varkey,
        ls_person_data     TYPE bapibus1006_central_person,
        ls_central_data    TYPE bapibus1006_central,
        ls_address_data    TYPE bapibus1006_address,
        ls_return          TYPE bapiret2,
        ls_commit_return   TYPE bapiret2,
        lt_return_bapi     TYPE STANDARD TABLE OF bapiret2.

  CLEAR: ev_bp_contact, ev_status_code, ev_status_message, ct_return.

  " Validate the RFC contract before starting any BAPI transaction.
  IF iv_bp_parent IS INITIAL OR iv_first_name IS INITIAL OR iv_last_name IS INITIAL.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'BP parent, prénom et nom sont obligatoires.'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  IF iv_bp_category IS NOT INITIAL AND iv_bp_category <> '1'.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'La catégorie BP doit être 1 (Personne).'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  IF ( iv_street IS NOT INITIAL OR iv_house_number IS NOT INITIAL
       OR iv_postal_code IS NOT INITIAL OR iv_city IS NOT INITIAL
       OR iv_region IS NOT INITIAL )
     AND iv_country IS INITIAL.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'Le pays est obligatoire lorsqu''une adresse est fournie.'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  " Apply and validate dates before any BAPI call. This also catches the case
  " where an empty start date defaults to today but the supplied end date is past.
  lv_valid_from = COND #( WHEN iv_date_from IS INITIAL THEN sy-datum
                          ELSE iv_date_from ).
  lv_valid_to = COND #( WHEN iv_date_to IS INITIAL THEN '99991231'
                        ELSE iv_date_to ).

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date = lv_valid_from
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  IF sy-subrc <> 0.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'La date de début est invalide.'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date = lv_valid_to
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  IF sy-subrc <> 0.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'La date de fin est invalide.'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  IF lv_valid_to < lv_valid_from.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'La date de fin doit être postérieure ou égale à la date de début.'.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING
      input  = iv_bp_parent
    IMPORTING
      output = lv_bp_parent.

  SELECT SINGLE partner
    FROM but000
    INTO @DATA(lv_parent_found)
    WHERE partner = @lv_bp_parent.

  IF sy-subrc <> 0.
    ev_status_code    = 'ERROR'.
    ev_status_message = |Le BP Parent { iv_bp_parent } n'existe pas.|.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  " Serialize contact creation for this parent. The generic table lock acts as
  " a semaphore for this RFC and closes the SELECT-then-CREATE race condition.
  lv_parent_lock_key = |{ sy-mandt }{ lv_bp_parent }|.
  CALL FUNCTION 'ENQUEUE_E_TABLE'
    EXPORTING
      tabname = 'BUT000'
      varkey  = lv_parent_lock_key
      _scope  = '1'
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.

  IF sy-subrc <> 0.
    IF sy-subrc = 1.
      ev_status_code    = 'LOCKED'.
      ev_status_message = 'Une création de contact est déjà en cours pour ce BP Parent. Réessayez ultérieurement.'.
    ELSE.
      ev_status_code    = 'ERROR'.
      ev_status_message = 'Impossible de poser le verrou de création pour ce BP Parent.'.
    ENDIF.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  " Idempotence métier : same person name with a relationship overlapping the
  " requested validity interval for this parent.
  SELECT SINGLE a~partner2
    FROM but050 AS a
    INNER JOIN but000 AS b ON b~partner = a~partner2
    INTO @lv_duplicate_id
    WHERE a~partner1   = @lv_bp_parent
      AND a~reltyp     = 'BUR001'
      AND a~date_from  <= @lv_valid_to
      AND a~date_to    >= @lv_valid_from
      AND b~name_first = @iv_first_name
      AND b~name_last  = @iv_last_name.

  IF sy-subrc = 0.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = lv_parent_lock_key
        _scope  = '1'.
    ev_bp_contact     = lv_duplicate_id.
    ev_status_code    = 'EXISTS'.
    ev_status_message = |Le contact { lv_duplicate_id } existe déjà pour ce BP Parent.|.
    ls_return-type    = 'S'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  ls_person_data-firstname = iv_first_name.
  ls_person_data-lastname  = iv_last_name.
  " IV_LANGUAGE is the correspondence language of a person, not an address
  " language. Filling ADDRESSDATA-LANGU for a person raises warning R111 010.
  ls_person_data-correspondlanguage = iv_language.
  ls_address_data-street     = iv_street.
  ls_address_data-house_no   = iv_house_number.
  ls_address_data-postl_cod1 = iv_postal_code.
  ls_address_data-city       = iv_city.
  ls_address_data-country    = iv_country.
  ls_address_data-region     = iv_region.
  lv_partnercategory = COND bu_type(  WHEN iv_bp_category IS INITIAL THEN '1'
                                     ELSE iv_bp_category ).
  lv_partnergroup    = COND bu_group( WHEN iv_grouping    IS INITIAL THEN 'ZC'
                                       ELSE iv_grouping ).
  lv_bp_role         = COND bu_partnerrole( WHEN iv_bp_role IS INITIAL THEN 'BUP001'
                                             ELSE iv_bp_role ).

  " Step 1: create the Person BP. SAP assigns lv_bp_contact internally.
  CLEAR: lv_bp_contact, lv_bp_contact_bapi, ev_bp_contact.
  CALL FUNCTION 'BAPI_BUPA_CREATE_FROM_DATA'
    EXPORTING
      partnercategory   = lv_partnercategory
      partnergroup      = lv_partnergroup
      centraldata       = ls_central_data
      centraldataperson = ls_person_data
      addressdata       = ls_address_data
    IMPORTING
      businesspartner   = lv_bp_contact_bapi
    TABLES
      return            = lt_return_bapi.
  APPEND LINES OF lt_return_bapi TO ct_return.
  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_bapi_failed = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.
  IF lv_bapi_failed = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = lv_parent_lock_key
        _scope  = '1'.
    ev_status_code    = 'ERROR'.
    ev_status_message = |Erreur de création du BP : { lv_error_msg }|.
    RETURN.
  ENDIF.

  " Keep the BAPI output in the RFC export from this point onward. Using the
  " BAPI's exact output type avoids losing the internally assigned BP number.
  lv_bp_contact = lv_bp_contact_bapi.
  ev_bp_contact = lv_bp_contact.

  IF lv_bp_contact IS INITIAL.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = lv_parent_lock_key
        _scope  = '1'.
    ev_status_code    = 'ERROR'.
    ev_status_message = 'La création du BP n''a retourné aucun numéro de contact.'.
    CLEAR ls_return.
    ls_return-type    = 'E'.
    ls_return-message = ev_status_message.
    APPEND ls_return TO ct_return.
    RETURN.
  ENDIF.

  " Step 2: add the contact role to the generated BP number.
  CLEAR: lt_return_bapi, ls_return, lv_error_msg, lv_bapi_failed.
  CALL FUNCTION 'BAPI_BUPA_ROLE_ADD_2'
    EXPORTING
      businesspartner     = lv_bp_contact
      businesspartnerrole = lv_bp_role
    TABLES
      return              = lt_return_bapi.

  APPEND LINES OF lt_return_bapi TO ct_return.
  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_bapi_failed = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.
  IF lv_bapi_failed = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = lv_parent_lock_key
        _scope  = '1'.
    ev_status_code    = 'ERROR'.
    ev_status_message = |Erreur d'ajout du rôle : { lv_error_msg }|.
    RETURN.
  ENDIF.

  " Step 3: create the contact relationship with the parent BP.
  CLEAR: lt_return_bapi, ls_return, lv_error_msg, lv_bapi_failed.
  CALL FUNCTION 'BAPI_BUPR_CONTP_CREATE'
    EXPORTING
      businesspartner = lv_bp_parent
      contactperson   = lv_bp_contact
      validfromdate   = lv_valid_from
      validuntildate = lv_valid_to
    TABLES
      return          = lt_return_bapi.

  APPEND LINES OF lt_return_bapi TO ct_return.
  LOOP AT lt_return_bapi INTO ls_return WHERE type = 'E' OR type = 'A' OR type = 'X'.
    lv_bapi_failed = abap_true.
    lv_error_msg = ls_return-message.
    EXIT.
  ENDLOOP.
  IF lv_bapi_failed = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'BUT000'
        varkey  = lv_parent_lock_key
        _scope  = '1'.
    ev_status_code    = 'ERROR'.
    ev_status_message = |Erreur de création de la relation : { lv_error_msg }|.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait = abap_true
    IMPORTING
      return = ls_commit_return.

  IF ls_commit_return-type IS NOT INITIAL OR ls_commit_return-message IS NOT INITIAL.
    APPEND ls_commit_return TO ct_return.
  ENDIF.

  CALL FUNCTION 'DEQUEUE_E_TABLE'
    EXPORTING
      tabname = 'BUT000'
      varkey  = lv_parent_lock_key
      _scope  = '1'.

  IF ls_commit_return-type = 'E' OR ls_commit_return-type = 'A'
     OR ls_commit_return-type = 'X'.
    CLEAR ev_bp_contact.
    ev_status_code    = 'ERROR'.
    ev_status_message = |Erreur lors du commit : { ls_commit_return-message }|.
    RETURN.
  ENDIF.

  ev_bp_contact     = lv_bp_contact.
  ev_status_code    = 'SUCCESS'.
  ev_status_message = |Contact créé et rattaché au BP Parent { iv_bp_parent }.|.
  CLEAR ls_return.
  ls_return-type    = 'S'.
  ls_return-message = |Contact BP { ev_bp_contact } créé et rattaché au BP Parent { iv_bp_parent }.|.
  APPEND ls_return TO ct_return.

ENDFUNCTION.
